//! The Cap'n Proto side of the service (contract ../contract/power.capnp).
//!
//! `Hub` is the state shared by all connections and its listeners. Backend events go in through
//! `Hub::apply`, which updates the state, sends every real change to every listener and derives the
//! events for notifications (events.rs). A new listener first gets the whole state (snapshot) and
//! then only the changes; Cap'n Proto keeps the calls on one capability in order.
//!
//! Changes of one battery or display go out at most every 50 ms with its latest state (throttle.rs):
//! a dragged brightness slider changes the display many times a second.
//!
//! Requests are checked here against the known state (the display exists, the value is in range, the
//! profile is offered) and then handed to the backend; the answer waits for the backend.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::{mpsc, oneshot};
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::backend::{BackendEvent, Command, Commands, ErrorCode, OpError};
use crate::events;
use crate::model::{
    Battery, BatteryState, Degradation, DeviceKind, Display, DisplayKind, Event, EventKind, KeyboardBacklight,
    PowerStatus, Profile, Profiles, WarningLevel,
};
use crate::power_capnp::{self as p, power_control, power_listener, power_service, profile_hold, subscription};
use crate::throttle::ChangeThrottle;

pub const CHANGE_INTERVAL: Duration = Duration::from_millis(50);

/// The whole state, as the clients see it
#[derive(Clone, Debug, PartialEq)]
pub struct State {
    pub status: PowerStatus,
    pub batteries: BTreeMap<String, Battery>,
    pub displays: BTreeMap<String, Display>,
    pub keyboard: KeyboardBacklight,
    pub profiles: Profiles,
}

impl State {
    pub fn new() -> State {
        State {
            status: PowerStatus::unavailable(),
            batteries: BTreeMap::new(),
            displays: BTreeMap::new(),
            keyboard: KeyboardBacklight::unavailable(),
            profiles: Profiles::unavailable(),
        }
    }

    /// The display a request means: by id, or "" for the built-in one (else the first)
    pub fn display(&self, id: &str) -> Option<&Display> {
        if id.is_empty() {
            self.displays.values().find(|d| d.kind == DisplayKind::BuiltIn).or_else(|| self.displays.values().next())
        } else {
            self.displays.get(id)
        }
    }
}

impl Default for State {
    fn default() -> Self {
        State::new()
    }
}

enum Change {
    Status,
    Battery(String),
    BatteryRemoved(String),
    Display(String),
    DisplayRemoved(String),
    Keyboard,
    Profiles,
    Event(Event),
}

pub struct Hub {
    state: State,
    /// Events also go here (notify.rs), with the battery they are about
    event_sink: Option<mpsc::UnboundedSender<(Event, Option<Battery>)>>,
    listeners: Vec<(u64, power_listener::Client)>,
    next_listener: u64,
    throttle: ChangeThrottle,
    flush_scheduled: bool,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    pub fn new() -> HubRef {
        Rc::new(RefCell::new(Hub {
            state: State::new(),
            event_sink: None,
            listeners: Vec::new(),
            next_listener: 0,
            throttle: ChangeThrottle::new(CHANGE_INTERVAL),
            flush_scheduled: false,
        }))
    }

    pub fn state(&self) -> &State {
        &self.state
    }

    /// The battery warnings go to the notification service through this (notify::run)
    pub fn set_event_sink(&mut self, sink: mpsc::UnboundedSender<(Event, Option<Battery>)>) {
        self.event_sink = Some(sink);
    }

    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    /// One event of the backend: update the state, tell the listeners what really changed
    pub fn apply(hub: &HubRef, event: BackendEvent) {
        let mut this = hub.borrow_mut();
        let mut changes = Vec::new();
        let now = Instant::now();
        match event {
            BackendEvent::Status(status) => {
                if this.state.status != status {
                    changes.extend(events::status_events(&this.state.status, &status).into_iter().map(Change::Event));
                    this.state.status = status;
                    changes.insert(0, Change::Status);
                }
            }
            BackendEvent::Battery(battery) => {
                let old = this.state.batteries.get(&battery.id).cloned();
                if old.as_ref() != Some(&battery) {
                    let key = format!("battery:{}", battery.id);
                    let send = match old {
                        None => {
                            this.throttle.added(&key, now);
                            true
                        }
                        Some(_) => this.throttle.changed(&key, now),
                    };
                    let derived = events::battery_events(old.as_ref(), &battery);
                    let id = battery.id.clone();
                    this.state.batteries.insert(id.clone(), battery);
                    if send {
                        changes.push(Change::Battery(id));
                    }
                    changes.extend(derived.into_iter().map(Change::Event));
                }
            }
            BackendEvent::BatteryRemoved(id) => {
                if this.state.batteries.remove(&id).is_some() {
                    this.throttle.removed(&format!("battery:{id}"));
                    changes.push(Change::BatteryRemoved(id));
                }
            }
            BackendEvent::Display(display) => {
                let old = this.state.displays.get(&display.id).cloned();
                if old.as_ref() != Some(&display) {
                    let key = format!("display:{}", display.id);
                    let send = match old {
                        None => {
                            this.throttle.added(&key, now);
                            true
                        }
                        Some(_) => this.throttle.changed(&key, now),
                    };
                    let id = display.id.clone();
                    this.state.displays.insert(id.clone(), display);
                    if send {
                        changes.push(Change::Display(id));
                    }
                }
            }
            BackendEvent::DisplayRemoved(id) => {
                if this.state.displays.remove(&id).is_some() {
                    this.throttle.removed(&format!("display:{id}"));
                    changes.push(Change::DisplayRemoved(id));
                }
            }
            BackendEvent::Keyboard(keyboard) => {
                if this.state.keyboard != keyboard {
                    this.state.keyboard = keyboard;
                    changes.push(Change::Keyboard);
                }
            }
            BackendEvent::Profiles(profiles) => {
                if this.state.profiles != profiles {
                    this.state.profiles = profiles;
                    changes.push(Change::Profiles);
                }
            }
        }
        for change in &changes {
            this.broadcast(hub, change);
            if let (Change::Event(event), Some(sink)) = (change, &this.event_sink) {
                let battery = this.state.batteries.get(&event.battery_id).cloned();
                let _ = sink.send((event.clone(), battery));
            }
        }
        schedule_flush(hub, &mut this);
    }

    /// Feeds the hub from the backend until the backend ends
    pub async fn run(hub: HubRef, mut events: mpsc::UnboundedReceiver<BackendEvent>) {
        while let Some(event) = events.recv().await {
            Hub::apply(&hub, event);
        }
    }

    fn broadcast(&self, hub: &HubRef, change: &Change) {
        for (id, listener) in &self.listeners {
            self.send(hub, *id, listener, change);
        }
    }

    fn send(&self, hub: &HubRef, id: u64, listener: &power_listener::Client, change: &Change) {
        match change {
            Change::Status => {
                let mut request = listener.status_changed_request();
                write_status(request.get().init_status(), &self.state.status);
                deliver(hub, id, request.send().promise);
            }
            Change::Battery(battery_id) => {
                let Some(battery) = self.state.batteries.get(battery_id) else { return };
                let mut request = listener.battery_changed_request();
                write_battery(request.get().init_battery(), battery);
                deliver(hub, id, request.send().promise);
            }
            Change::BatteryRemoved(battery_id) => {
                let mut request = listener.battery_removed_request();
                request.get().set_id(battery_id);
                deliver(hub, id, request.send().promise);
            }
            Change::Display(display_id) => {
                let Some(display) = self.state.displays.get(display_id) else { return };
                let mut request = listener.display_changed_request();
                write_display(request.get().init_display(), display);
                deliver(hub, id, request.send().promise);
            }
            Change::DisplayRemoved(display_id) => {
                let mut request = listener.display_removed_request();
                request.get().set_id(display_id);
                deliver(hub, id, request.send().promise);
            }
            Change::Keyboard => {
                let mut request = listener.keyboard_changed_request();
                write_keyboard(request.get().init_keyboard(), &self.state.keyboard);
                deliver(hub, id, request.send().promise);
            }
            Change::Profiles => {
                let mut request = listener.profiles_changed_request();
                write_profiles(request.get().init_profiles(), &self.state.profiles);
                deliver(hub, id, request.send().promise);
            }
            Change::Event(event) => {
                let mut request = listener.event_request();
                write_event(request.get().init_event(), event);
                deliver(hub, id, request.send().promise);
            }
        }
    }

    /// Sends the waiting changes that are due, each with the latest state of its object
    fn flush(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        this.flush_scheduled = false;
        for key in this.throttle.take_due(Instant::now()) {
            let change = match key.split_once(':') {
                Some(("battery", id)) => Change::Battery(id.to_string()),
                Some(("display", id)) => Change::Display(id.to_string()),
                _ => continue,
            };
            this.broadcast(hub, &change);
        }
        schedule_flush(hub, &mut this);
    }

    fn add_listener(hub: &HubRef, client: power_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        write_snapshot(request.get().init_snapshot(), &this.state);
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }
}

fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled {
        return;
    }
    let Some(deadline) = this.throttle.next_deadline() else { return };
    this.flush_scheduled = true;
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        tokio::time::sleep_until(tokio::time::Instant::from_std(deadline)).await;
        if let Some(hub) = hub.upgrade() {
            Hub::flush(&hub);
        }
    });
}

/// Runs the call in the background; when it fails, the listener is gone
fn deliver<T: 'static>(hub: &HubRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        if promise.await.is_err() {
            if let Some(hub) = hub.upgrade() {
                hub.borrow_mut().remove_listener(id);
            }
        }
    });
}

// --- Plain values into the contract ---

fn write_kind(kind: DeviceKind) -> p::DeviceKind {
    match kind {
        DeviceKind::Battery => p::DeviceKind::Battery,
        DeviceKind::Ups => p::DeviceKind::Ups,
        DeviceKind::Mouse => p::DeviceKind::Mouse,
        DeviceKind::Keyboard => p::DeviceKind::Keyboard,
        DeviceKind::Touchpad => p::DeviceKind::Touchpad,
        DeviceKind::GamingInput => p::DeviceKind::GamingInput,
        DeviceKind::Pen => p::DeviceKind::Pen,
        DeviceKind::Headset => p::DeviceKind::Headset,
        DeviceKind::Headphones => p::DeviceKind::Headphones,
        DeviceKind::Speakers => p::DeviceKind::Speakers,
        DeviceKind::Phone => p::DeviceKind::Phone,
        DeviceKind::Tablet => p::DeviceKind::Tablet,
        DeviceKind::MediaPlayer => p::DeviceKind::MediaPlayer,
        DeviceKind::Computer => p::DeviceKind::Computer,
        DeviceKind::Wearable => p::DeviceKind::Wearable,
        DeviceKind::Other => p::DeviceKind::Other,
    }
}

fn write_state(state: BatteryState) -> p::BatteryState {
    match state {
        BatteryState::Unknown => p::BatteryState::Unknown,
        BatteryState::Charging => p::BatteryState::Charging,
        BatteryState::Discharging => p::BatteryState::Discharging,
        BatteryState::Empty => p::BatteryState::Empty,
        BatteryState::Full => p::BatteryState::Full,
        BatteryState::PendingCharge => p::BatteryState::PendingCharge,
        BatteryState::PendingDischarge => p::BatteryState::PendingDischarge,
    }
}

fn write_level(level: WarningLevel) -> p::WarningLevel {
    match level {
        WarningLevel::None => p::WarningLevel::None,
        WarningLevel::Low => p::WarningLevel::Low,
        WarningLevel::Critical => p::WarningLevel::Critical,
        WarningLevel::Action => p::WarningLevel::Action,
    }
}

pub fn write_battery(mut b: p::battery::Builder, battery: &Battery) {
    b.set_id(&battery.id);
    b.set_kind(write_kind(battery.kind));
    b.set_vendor(&battery.vendor);
    b.set_model(&battery.model);
    b.set_present(battery.present);
    b.set_power_supply(battery.power_supply);
    b.set_percentage(battery.percentage);
    b.set_state(write_state(battery.state));
    b.set_warning_level(write_level(battery.warning_level));
    b.set_time_to_empty(battery.time_to_empty);
    b.set_time_to_full(battery.time_to_full);
    b.set_energy_rate(battery.energy_rate);
    b.set_capacity(battery.capacity);
}

fn write_status(mut b: p::power_status::Builder, status: &PowerStatus) {
    b.set_upower_available(status.upower_available);
    b.set_on_battery(status.on_battery);
    b.set_lid_present(status.lid_present);
    b.set_lid_closed(status.lid_closed);
    write_battery(b.init_summary(), &status.summary);
}

fn write_display(mut b: p::display::Builder, display: &Display) {
    b.set_id(&display.id);
    b.set_kind(match display.kind {
        DisplayKind::BuiltIn => p::DisplayKind::BuiltIn,
        DisplayKind::External => p::DisplayKind::External,
    });
    b.set_device(&display.device);
    b.set_brightness(display.fraction());
    b.set_raw_brightness(display.raw);
    b.set_raw_maximum(display.raw_max);
    b.set_minimum(display.minimum());
}

fn write_keyboard(mut b: p::keyboard_backlight::Builder, keyboard: &KeyboardBacklight) {
    b.set_available(keyboard.available);
    b.set_brightness(keyboard.fraction());
    b.set_raw_brightness(keyboard.raw);
    b.set_raw_maximum(keyboard.raw_max);
}

fn write_profile(profile: Profile) -> p::Profile {
    match profile {
        Profile::PowerSaver => p::Profile::PowerSaver,
        Profile::Balanced => p::Profile::Balanced,
        Profile::Performance => p::Profile::Performance,
    }
}

fn read_profile(profile: p::Profile) -> Profile {
    match profile {
        p::Profile::PowerSaver => Profile::PowerSaver,
        p::Profile::Balanced => Profile::Balanced,
        p::Profile::Performance => Profile::Performance,
    }
}

fn write_profiles(mut b: p::profiles::Builder, profiles: &Profiles) {
    b.set_available(profiles.available);
    b.set_active(write_profile(profiles.active));
    {
        let mut offered = b.reborrow().init_offered(profiles.offered.len() as u32);
        for (i, profile) in profiles.offered.iter().enumerate() {
            offered.set(i as u32, write_profile(*profile));
        }
    }
    b.set_degraded(match profiles.degraded {
        Degradation::None => p::Degradation::None,
        Degradation::LapDetected => p::Degradation::LapDetected,
        Degradation::HighOperatingTemperature => p::Degradation::HighOperatingTemperature,
        Degradation::Other => p::Degradation::Other,
    });
    let mut holds = b.init_holds(profiles.holds.len() as u32);
    for (i, hold) in profiles.holds.iter().enumerate() {
        let mut h = holds.reborrow().get(i as u32);
        h.set_profile(write_profile(hold.profile));
        h.set_reason(&hold.reason);
        h.set_application_id(&hold.application_id);
    }
}

fn write_event(mut b: p::event::Builder, event: &Event) {
    b.set_kind(match event.kind {
        EventKind::ChargerConnected => p::EventKind::ChargerConnected,
        EventKind::ChargerDisconnected => p::EventKind::ChargerDisconnected,
        EventKind::BatteryLow => p::EventKind::BatteryLow,
        EventKind::BatteryCritical => p::EventKind::BatteryCritical,
        EventKind::BatteryAction => p::EventKind::BatteryAction,
        EventKind::BatteryFull => p::EventKind::BatteryFull,
        EventKind::DeviceBatteryLow => p::EventKind::DeviceBatteryLow,
    });
    b.set_battery_id(&event.battery_id);
    b.set_percentage(event.percentage);
}

fn write_snapshot(mut b: p::snapshot::Builder, state: &State) {
    write_status(b.reborrow().init_status(), &state.status);
    {
        let mut batteries = b.reborrow().init_batteries(state.batteries.len() as u32);
        for (i, battery) in state.batteries.values().enumerate() {
            write_battery(batteries.reborrow().get(i as u32), battery);
        }
    }
    {
        let mut displays = b.reborrow().init_displays(state.displays.len() as u32);
        for (i, display) in state.displays.values().enumerate() {
            write_display(displays.reborrow().get(i as u32), display);
        }
    }
    write_keyboard(b.reborrow().init_keyboard(), &state.keyboard);
    write_profiles(b.init_profiles(), &state.profiles);
}

fn write_result(mut b: p::result::Builder, result: &Result<(), OpError>) {
    match result {
        Ok(()) => b.set_error(p::ErrorCode::None),
        Err(error) => {
            b.set_error(match error.code {
                ErrorCode::NotFound => p::ErrorCode::NotFound,
                ErrorCode::NotAllowed => p::ErrorCode::NotAllowed,
                ErrorCode::InvalidArgument => p::ErrorCode::InvalidArgument,
                ErrorCode::NotSupported => p::ErrorCode::NotSupported,
                ErrorCode::Unavailable => p::ErrorCode::Unavailable,
                ErrorCode::Failed => p::ErrorCode::Failed,
            });
            b.set_message(&error.message);
        }
    }
}

// --- PowerService: the bootstrap capability of every connection ---

pub struct PowerService {
    hub: HubRef,
    commands: Commands,
    backend: String,
}

impl PowerService {
    pub fn client(hub: HubRef, commands: Commands, backend: &str) -> power_service::Client {
        capnp_rpc::new_client(PowerService { hub, commands, backend: backend.to_string() })
    }
}

/// Released by the client (or with its connection): the listener stops getting calls
struct SubscriptionImpl {
    hub: Weak<RefCell<Hub>>,
    id: u64,
}

impl Drop for SubscriptionImpl {
    fn drop(&mut self) {
        if let Some(hub) = self.hub.upgrade() {
            hub.borrow_mut().remove_listener(self.id);
        }
    }
}

impl subscription::Server for SubscriptionImpl {}

impl power_service::Server for PowerService {
    async fn info(
        self: Rc<Self>,
        _: power_service::InfoParams,
        mut results: power_service::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut b = results.get();
        b.set_service_version(env!("CARGO_PKG_VERSION"));
        b.set_backend(&self.backend);
        Ok(())
    }

    async fn watch(
        self: Rc<Self>,
        params: power_service::WatchParams,
        mut results: power_service::WatchResults,
    ) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(SubscriptionImpl { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn control(
        self: Rc<Self>,
        _: power_service::ControlParams,
        mut results: power_service::ControlResults,
    ) -> Result<(), capnp::Error> {
        results.get().set_control(capnp_rpc::new_client(Control { hub: self.hub.clone(), commands: self.commands.clone() }));
        Ok(())
    }
}

// --- PowerControl ---

struct Control {
    hub: HubRef,
    commands: Commands,
}

/// Released by the client (or with its connection): the profile is no longer held
struct HoldImpl {
    commands: Commands,
    cookie: u32,
}

impl Drop for HoldImpl {
    fn drop(&mut self) {
        let _ = self.commands.send(Command::ReleaseProfile { cookie: self.cookie });
    }
}

impl profile_hold::Server for HoldImpl {}

impl Control {
    async fn ask<T>(&self, make: impl FnOnce(oneshot::Sender<Result<T, OpError>>) -> Command) -> Result<T, OpError> {
        let (reply, answer) = oneshot::channel();
        self.commands.send(make(reply))?;
        answer.await.unwrap_or_else(|_| Err(OpError::new(ErrorCode::Unavailable, "the backend has stopped")))
    }

    async fn set_brightness_raw(&self, display_id: &str, target: impl FnOnce(&Display) -> u32) -> Result<(), OpError> {
        let (id, raw) = {
            let hub = self.hub.borrow();
            let display = hub
                .state
                .display(display_id)
                .ok_or_else(|| OpError::new(ErrorCode::NotFound, format!("no display \"{display_id}\"")))?;
            (display.id.clone(), target(display))
        };
        self.ask(|reply| Command::SetBrightness { display_id: id, raw, reply }).await
    }
}

fn check_fraction(value: f64) -> Result<f64, OpError> {
    if value.is_finite() && (0.0..=1.0).contains(&value) {
        Ok(value)
    } else {
        Err(OpError::new(ErrorCode::InvalidArgument, format!("{value} is not between 0 and 1")))
    }
}

impl power_control::Server for Control {
    async fn set_brightness(
        self: Rc<Self>,
        params: power_control::SetBrightnessParams,
        mut results: power_control::SetBrightnessResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let display_id = params.get_display_id()?.to_string()?;
        let result = match check_fraction(params.get_brightness()) {
            Ok(value) => self.set_brightness_raw(&display_id, |d| d.raw_for(value)).await,
            Err(error) => Err(error),
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn step_brightness(
        self: Rc<Self>,
        params: power_control::StepBrightnessParams,
        mut results: power_control::StepBrightnessResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let display_id = params.get_display_id()?.to_string()?;
        let steps = params.get_steps();
        let result = self.set_brightness_raw(&display_id, |d| d.raw_after_steps(d.raw, steps)).await;
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn set_keyboard_brightness(
        self: Rc<Self>,
        params: power_control::SetKeyboardBrightnessParams,
        mut results: power_control::SetKeyboardBrightnessResults,
    ) -> Result<(), capnp::Error> {
        let value = params.get()?.get_brightness();
        let keyboard = self.hub.borrow().state.keyboard.clone();
        let result = match check_fraction(value) {
            Err(error) => Err(error),
            Ok(_) if !keyboard.available => Err(OpError::new(ErrorCode::NotSupported, "no keyboard backlight")),
            Ok(value) => self.ask(|reply| Command::SetKeyboardBrightness { raw: keyboard.raw_for(value), reply }).await,
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn set_profile(
        self: Rc<Self>,
        params: power_control::SetProfileParams,
        mut results: power_control::SetProfileResults,
    ) -> Result<(), capnp::Error> {
        let profile = read_profile(params.get()?.get_profile()?);
        let result = match self.check_profile(profile) {
            Err(error) => Err(error),
            Ok(()) => self.ask(|reply| Command::SetProfile { profile, reply }).await,
        };
        write_result(results.get().init_result(), &result);
        Ok(())
    }

    async fn hold_profile(
        self: Rc<Self>,
        params: power_control::HoldProfileParams,
        mut results: power_control::HoldProfileResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let profile = read_profile(params.get_profile()?);
        let reason = params.get_reason()?.to_string()?;
        let application_id = params.get_application_id()?.to_string()?;
        let result = match self.check_profile(profile) {
            Err(error) => Err(error),
            Ok(()) => {
                self.ask(|reply| Command::HoldProfile { profile, reason, application_id, reply }).await
            }
        };
        match result {
            Ok(cookie) => {
                write_result(results.get().init_result(), &Ok(()));
                results.get().set_hold(capnp_rpc::new_client(HoldImpl { commands: self.commands.clone(), cookie }));
            }
            Err(error) => write_result(results.get().init_result(), &Err(error)),
        }
        Ok(())
    }
}

impl Control {
    fn check_profile(&self, profile: Profile) -> Result<(), OpError> {
        let hub = self.hub.borrow();
        let profiles = &hub.state.profiles;
        if !profiles.available {
            return Err(OpError::new(ErrorCode::Unavailable, "power-profiles-daemon does not run"));
        }
        if !profiles.offered.contains(&profile) {
            return Err(OpError::new(ErrorCode::NotSupported, format!("{} is not offered here", profile.ppd_name())));
        }
        Ok(())
    }
}

// --- Connections ---

/// Serves one client connection in the background
pub fn serve(stream: tokio::net::UnixStream, service: power_service::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Server,
        Default::default(),
    );
    let rpc_system = RpcSystem::new(Box::new(network), Some(service.client));
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
}
