//! A simulated laptop: a battery and a charger, a wireless mouse, a backlit panel and keyboard,
//! and power-profiles-daemon.
//!
//! For the tests of the service and for working on the user interface in a nested session without
//! touching the machine (MAIA_POWER_BACKEND=fake). It follows the rules of the real sources where
//! the interface depends on them:
//!
//! - UPower's warning levels on battery: low at 20 %, critical at 5 %, action at 2 %; none on the
//!   charger. The battery charges on the charger, is full at 100 %.
//! - power-profiles-daemon: holds override the chosen profile, power-saver holds win over
//!   performance ones; choosing a profile by hand releases every hold.
//! - A brightness change takes a moment (`Timing::step`), as a write through logind does.
//!
//! Tests drive it through `FakeHandle` (unplug the charger, drain the battery, add a device, change
//! the brightness from outside); with `Timing::realistic` the battery also drains and charges by itself.

use std::time::Duration;

use tokio::sync::mpsc;

use crate::backend::{BackendEvent, Command, ErrorCode, OpError};
use crate::model::{
    Battery, BatteryState, Degradation, DeviceKind, Display, DisplayKind, HeldProfile, KeyboardBacklight, PowerStatus,
    Profile, Profiles, WarningLevel,
};

pub const NAME: &str = "fake";
pub const BATTERY: &str = "battery_BAT0";
pub const MOUSE: &str = "mouse_dev_F4_73_35_00_00_01";
pub const PANEL: &str = "backlight:fake_backlight";

#[derive(Clone, Copy, Debug)]
pub struct Timing {
    /// How long a change takes to be applied
    pub step: Duration,
    /// How often the battery moves by itself (None: only when told)
    pub tick: Option<Duration>,
}

impl Timing {
    pub fn instant() -> Timing {
        Timing { step: Duration::from_millis(1), tick: None }
    }

    pub fn realistic() -> Timing {
        Timing { step: Duration::from_millis(30), tick: Some(Duration::from_secs(20)) }
    }
}

/// What a test does to the simulated machine
#[derive(Clone, Debug)]
pub enum FakeAction {
    Charger(bool),
    Percentage(f64),
    AddBattery(Battery),
    RemoveBattery(String),
    /// The brightness changed outside of Maia (the keys, powerdevil dimming)
    ExternalBrightness(u32),
    Degraded(Degradation),
    /// Every following command fails with this code (None: they succeed again)
    Refuse(Option<ErrorCode>),
}

pub type FakeHandle = mpsc::UnboundedSender<FakeAction>;

struct Machine {
    on_charger: bool,
    percentage: f64,
    devices: Vec<Battery>,
    panel_raw: u32,
    keyboard_raw: u32,
    chosen: Profile,
    holds: Vec<(u32, HeldProfile)>,
    next_cookie: u32,
    degraded: Degradation,
    refuse: Option<ErrorCode>,
}

const PANEL_MAX: u32 = 96000;
const KEYBOARD_MAX: u32 = 2;

impl Machine {
    fn new() -> Machine {
        Machine {
            on_charger: false,
            percentage: 80.0,
            devices: vec![Battery {
                id: MOUSE.into(),
                kind: DeviceKind::Mouse,
                vendor: "Logitech".into(),
                model: "MX Master 3".into(),
                present: true,
                power_supply: false,
                percentage: 45.0,
                state: BatteryState::Discharging,
                warning_level: WarningLevel::None,
                ..Battery::absent(MOUSE)
            }],
            panel_raw: 48000,
            keyboard_raw: 1,
            chosen: Profile::Balanced,
            holds: Vec::new(),
            next_cookie: 1,
            degraded: Degradation::None,
            refuse: None,
        }
    }

    fn battery(&self, id: &str) -> Battery {
        let state = if self.on_charger {
            if self.percentage >= 100.0 { BatteryState::Full } else { BatteryState::Charging }
        } else {
            BatteryState::Discharging
        };
        let warning_level = match (self.on_charger, self.percentage) {
            (true, _) => WarningLevel::None,
            (false, p) if p <= 2.0 => WarningLevel::Action,
            (false, p) if p <= 5.0 => WarningLevel::Critical,
            (false, p) if p <= 20.0 => WarningLevel::Low,
            _ => WarningLevel::None,
        };
        Battery {
            id: id.into(),
            kind: DeviceKind::Battery,
            vendor: "Simulated".into(),
            model: "Fake Battery".into(),
            present: true,
            power_supply: true,
            percentage: self.percentage,
            state,
            warning_level,
            time_to_empty: if self.on_charger { 0 } else { (self.percentage * 216.0) as i64 },
            time_to_full: if self.on_charger && self.percentage < 100.0 { ((100.0 - self.percentage) * 90.0) as i64 } else { 0 },
            energy_rate: if state == BatteryState::Full { 0.0 } else { 7.5 },
            capacity: 92.0,
        }
    }

    fn status(&self) -> PowerStatus {
        PowerStatus {
            upower_available: true,
            on_battery: !self.on_charger,
            lid_present: true,
            lid_closed: false,
            summary: self.battery("DisplayDevice"),
        }
    }

    fn panel(&self) -> Display {
        Display { id: PANEL.into(), kind: DisplayKind::BuiltIn, device: "fake_backlight".into(), raw: self.panel_raw, raw_max: PANEL_MAX }
    }

    fn keyboard(&self) -> KeyboardBacklight {
        KeyboardBacklight { available: true, raw: self.keyboard_raw, raw_max: KEYBOARD_MAX }
    }

    /// power-profiles-daemon: a power-saver hold wins, then a performance one, then the user's choice
    fn profiles(&self) -> Profiles {
        let held = |p| self.holds.iter().any(|(_, h)| h.profile == p);
        let active = if held(Profile::PowerSaver) {
            Profile::PowerSaver
        } else if held(Profile::Performance) {
            Profile::Performance
        } else {
            self.chosen
        };
        Profiles {
            available: true,
            active,
            offered: vec![Profile::PowerSaver, Profile::Balanced, Profile::Performance],
            degraded: self.degraded,
            holds: self.holds.iter().map(|(_, h)| h.clone()).collect(),
        }
    }
}

fn send_all(events: &mpsc::UnboundedSender<BackendEvent>, machine: &Machine) {
    let _ = events.send(BackendEvent::Status(machine.status()));
    let _ = events.send(BackendEvent::Battery(machine.battery(BATTERY)));
    for device in &machine.devices {
        let _ = events.send(BackendEvent::Battery(device.clone()));
    }
    let _ = events.send(BackendEvent::Display(machine.panel()));
    let _ = events.send(BackendEvent::Keyboard(machine.keyboard()));
    let _ = events.send(BackendEvent::Profiles(machine.profiles()));
}

fn send_battery(events: &mpsc::UnboundedSender<BackendEvent>, machine: &Machine) {
    let _ = events.send(BackendEvent::Battery(machine.battery(BATTERY)));
    let _ = events.send(BackendEvent::Status(machine.status()));
}

pub async fn run(
    events: mpsc::UnboundedSender<BackendEvent>,
    mut commands: mpsc::UnboundedReceiver<Command>,
    mut actions: mpsc::UnboundedReceiver<FakeAction>,
    timing: Timing,
) {
    let mut machine = Machine::new();
    send_all(&events, &machine);
    let mut tick = timing.tick.map(tokio::time::interval);
    if let Some(tick) = &mut tick {
        tick.tick().await;
    }
    loop {
        tokio::select! {
            command = commands.recv() => {
                let Some(command) = command else { return };
                if let Some(code) = machine.refuse {
                    refuse(command, code);
                    continue;
                }
                match command {
                    Command::SetBrightness { display_id, raw, reply } => {
                        if display_id != PANEL {
                            let _ = reply.send(Err(OpError::new(ErrorCode::NotFound, display_id)));
                            continue;
                        }
                        tokio::time::sleep(timing.step).await;
                        machine.panel_raw = raw;
                        let _ = events.send(BackendEvent::Display(machine.panel()));
                        let _ = reply.send(Ok(()));
                    }
                    Command::SetKeyboardBrightness { raw, reply } => {
                        machine.keyboard_raw = raw.min(KEYBOARD_MAX);
                        let _ = events.send(BackendEvent::Keyboard(machine.keyboard()));
                        let _ = reply.send(Ok(()));
                    }
                    Command::SetProfile { profile, reply } => {
                        machine.chosen = profile;
                        machine.holds.clear();
                        let _ = events.send(BackendEvent::Profiles(machine.profiles()));
                        let _ = reply.send(Ok(()));
                    }
                    Command::HoldProfile { profile, reason, application_id, reply } => {
                        let cookie = machine.next_cookie;
                        machine.next_cookie += 1;
                        machine.holds.push((cookie, HeldProfile { profile, reason, application_id }));
                        let _ = events.send(BackendEvent::Profiles(machine.profiles()));
                        let _ = reply.send(Ok(cookie));
                    }
                    Command::ReleaseProfile { cookie } => {
                        machine.holds.retain(|(c, _)| *c != cookie);
                        let _ = events.send(BackendEvent::Profiles(machine.profiles()));
                    }
                }
            }
            action = actions.recv() => {
                let Some(action) = action else {
                    // No more test actions: go on serving commands
                    actions = mpsc::unbounded_channel().1;
                    continue;
                };
                match action {
                    FakeAction::Charger(on) => {
                        machine.on_charger = on;
                        send_battery(&events, &machine);
                    }
                    FakeAction::Percentage(percentage) => {
                        machine.percentage = percentage.clamp(0.0, 100.0);
                        send_battery(&events, &machine);
                    }
                    FakeAction::AddBattery(battery) => {
                        machine.devices.retain(|d| d.id != battery.id);
                        machine.devices.push(battery.clone());
                        let _ = events.send(BackendEvent::Battery(battery));
                    }
                    FakeAction::RemoveBattery(id) => {
                        machine.devices.retain(|d| d.id != id);
                        let _ = events.send(BackendEvent::BatteryRemoved(id));
                    }
                    FakeAction::ExternalBrightness(raw) => {
                        machine.panel_raw = raw.min(PANEL_MAX);
                        let _ = events.send(BackendEvent::Display(machine.panel()));
                    }
                    FakeAction::Degraded(degraded) => {
                        machine.degraded = degraded;
                        let _ = events.send(BackendEvent::Profiles(machine.profiles()));
                    }
                    FakeAction::Refuse(code) => machine.refuse = code,
                }
            }
            _ = async { tick.as_mut().unwrap().tick().await }, if tick.is_some() => {
                // A slow life: down by 1 % on the battery, up by 2 % on the charger
                machine.percentage = if machine.on_charger {
                    (machine.percentage + 2.0).min(100.0)
                } else {
                    (machine.percentage - 1.0).max(0.0)
                };
                send_battery(&events, &machine);
            }
        }
    }
}

fn refuse(command: Command, code: ErrorCode) {
    let error = || OpError::new(code, "refused by the fake backend");
    match command {
        Command::SetBrightness { reply, .. }
        | Command::SetKeyboardBrightness { reply, .. }
        | Command::SetProfile { reply, .. } => {
            let _ = reply.send(Err(error()));
        }
        Command::HoldProfile { reply, .. } => {
            let _ = reply.send(Err(error()));
        }
        Command::ReleaseProfile { .. } => {}
    }
}
