//! A client of the power service for the tests: it watches the state like a shell keeps it and
//! makes the requests a shell makes.

#![allow(dead_code)]

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::rc::Rc;
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_power::power_capnp::{self as p, power_control, power_listener, power_service};

pub const TIMEOUT: Duration = Duration::from_secs(5);

pub fn local<F: std::future::Future>(future: F) -> F::Output {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    let local = tokio::task::LocalSet::new();
    let output = local.block_on(&runtime, future);
    // The tasks left (zbus streams) are dropped inside the runtime: their drop spawns a task
    let _entered = runtime.enter();
    drop(local);
    output
}

/// What the client has seen, kept like a shell would keep it
#[derive(Default, Debug)]
pub struct Seen {
    pub snapshots: u32,
    pub on_battery: bool,
    pub summary_percentage: f64,
    pub summary_level: Option<p::WarningLevel>,
    pub batteries: BTreeMap<String, (p::DeviceKind, f64)>,
    pub displays: BTreeMap<String, (f64, u32, u32, f64)>,
    pub keyboard: Option<(bool, f64)>,
    pub active_profile: Option<p::Profile>,
    pub offered: Vec<p::Profile>,
    pub holds: Vec<String>,
    pub degraded: Option<p::Degradation>,
    pub events: Vec<(p::EventKind, String)>,
}

struct Listener(Rc<RefCell<Seen>>);

fn read_status(seen: &mut Seen, status: p::power_status::Reader) -> capnp::Result<()> {
    seen.on_battery = status.get_on_battery();
    let summary = status.get_summary()?;
    seen.summary_percentage = summary.get_percentage();
    seen.summary_level = Some(summary.get_warning_level()?);
    Ok(())
}

fn read_battery(seen: &mut Seen, b: p::battery::Reader) -> capnp::Result<()> {
    seen.batteries.insert(b.get_id()?.to_string()?, (b.get_kind()?, b.get_percentage()));
    Ok(())
}

fn read_display(seen: &mut Seen, d: p::display::Reader) -> capnp::Result<()> {
    seen.displays.insert(d.get_id()?.to_string()?, (d.get_brightness(), d.get_raw_brightness(), d.get_raw_maximum(), d.get_minimum()));
    Ok(())
}

fn read_profiles(seen: &mut Seen, profiles: p::profiles::Reader) -> capnp::Result<()> {
    seen.active_profile = Some(profiles.get_active()?);
    seen.offered = profiles.get_offered()?.iter().collect::<Result<_, _>>()?;
    seen.holds = profiles.get_holds()?.iter().map(|h| Ok(h.get_reason()?.to_string()?)).collect::<capnp::Result<_>>()?;
    seen.degraded = Some(profiles.get_degraded()?);
    Ok(())
}

impl power_listener::Server for Listener {
    async fn snapshot(
        self: Rc<Self>,
        params: power_listener::SnapshotParams,
        _: power_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        let snapshot = params.get()?.get_snapshot()?;
        let mut seen = self.0.borrow_mut();
        seen.snapshots += 1;
        read_status(&mut seen, snapshot.get_status()?)?;
        for b in snapshot.get_batteries()? {
            read_battery(&mut seen, b)?;
        }
        for d in snapshot.get_displays()? {
            read_display(&mut seen, d)?;
        }
        let k = snapshot.get_keyboard()?;
        seen.keyboard = Some((k.get_available(), k.get_brightness()));
        read_profiles(&mut seen, snapshot.get_profiles()?)
    }

    async fn status_changed(
        self: Rc<Self>,
        params: power_listener::StatusChangedParams,
        _: power_listener::StatusChangedResults,
    ) -> Result<(), capnp::Error> {
        read_status(&mut self.0.borrow_mut(), params.get()?.get_status()?)
    }

    async fn battery_changed(
        self: Rc<Self>,
        params: power_listener::BatteryChangedParams,
        _: power_listener::BatteryChangedResults,
    ) -> Result<(), capnp::Error> {
        read_battery(&mut self.0.borrow_mut(), params.get()?.get_battery()?)
    }

    async fn battery_removed(
        self: Rc<Self>,
        params: power_listener::BatteryRemovedParams,
        _: power_listener::BatteryRemovedResults,
    ) -> Result<(), capnp::Error> {
        let id = params.get()?.get_id()?.to_string()?;
        self.0.borrow_mut().batteries.remove(&id);
        Ok(())
    }

    async fn display_changed(
        self: Rc<Self>,
        params: power_listener::DisplayChangedParams,
        _: power_listener::DisplayChangedResults,
    ) -> Result<(), capnp::Error> {
        read_display(&mut self.0.borrow_mut(), params.get()?.get_display()?)
    }

    async fn display_removed(
        self: Rc<Self>,
        params: power_listener::DisplayRemovedParams,
        _: power_listener::DisplayRemovedResults,
    ) -> Result<(), capnp::Error> {
        let id = params.get()?.get_id()?.to_string()?;
        self.0.borrow_mut().displays.remove(&id);
        Ok(())
    }

    async fn keyboard_changed(
        self: Rc<Self>,
        params: power_listener::KeyboardChangedParams,
        _: power_listener::KeyboardChangedResults,
    ) -> Result<(), capnp::Error> {
        let k = params.get()?.get_keyboard()?;
        self.0.borrow_mut().keyboard = Some((k.get_available(), k.get_brightness()));
        Ok(())
    }

    async fn profiles_changed(
        self: Rc<Self>,
        params: power_listener::ProfilesChangedParams,
        _: power_listener::ProfilesChangedResults,
    ) -> Result<(), capnp::Error> {
        read_profiles(&mut self.0.borrow_mut(), params.get()?.get_profiles()?)
    }

    async fn event(
        self: Rc<Self>,
        params: power_listener::EventParams,
        _: power_listener::EventResults,
    ) -> Result<(), capnp::Error> {
        let e = params.get()?.get_event()?;
        self.0.borrow_mut().events.push((e.get_kind()?, e.get_battery_id()?.to_string()?));
        Ok(())
    }
}

pub struct Client {
    pub seen: Rc<RefCell<Seen>>,
    pub control: power_control::Client,
    pub service: power_service::Client,
    _subscription: p::subscription::Client,
}

/// Connects a client to a service over a socket pair and watches it
pub async fn connect(service: power_service::Client) -> Client {
    let (ours, theirs) = tokio::net::UnixStream::pair().unwrap();
    maia_power::rpc::serve(theirs, service);
    let (reader, writer) = ours.compat().split();
    let network = Box::new(twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    ));
    let mut rpc_system = RpcSystem::new(network, None);
    let service: power_service::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
    let seen = Rc::new(RefCell::new(Seen::default()));
    let mut request = service.watch_request();
    request.get().set_listener(capnp_rpc::new_client(Listener(seen.clone())));
    let subscription = request.send().promise.await.unwrap().get().unwrap().get_subscription().unwrap();
    let control = service.control_request().send().promise.await.unwrap().get().unwrap().get_control().unwrap();
    Client { seen, control, service, _subscription: subscription }
}

impl Client {
    pub async fn wait(&self, what: &str, condition: impl Fn(&Seen) -> bool) {
        let start = Instant::now();
        while !condition(&self.seen.borrow()) {
            assert!(start.elapsed() < TIMEOUT, "waiting for {what}: {:?}", self.seen.borrow());
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    }

    pub async fn set_brightness(&self, display: &str, value: f64) -> p::ErrorCode {
        let mut request = self.control.set_brightness_request();
        request.get().set_display_id(display);
        request.get().set_brightness(value);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    pub async fn step_brightness(&self, steps: i32) -> p::ErrorCode {
        let mut request = self.control.step_brightness_request();
        request.get().set_steps(steps);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    pub async fn set_keyboard(&self, value: f64) -> p::ErrorCode {
        let mut request = self.control.set_keyboard_brightness_request();
        request.get().set_brightness(value);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    pub async fn set_profile(&self, profile: p::Profile) -> p::ErrorCode {
        let mut request = self.control.set_profile_request();
        request.get().set_profile(profile);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    pub async fn hold_profile(&self, profile: p::Profile, reason: &str) -> (p::ErrorCode, Option<p::profile_hold::Client>) {
        let mut request = self.control.hold_profile_request();
        request.get().set_profile(profile);
        request.get().set_reason(reason);
        request.get().set_application_id("org.maia.test");
        let reply = request.send().promise.await.unwrap();
        let reply = reply.get().unwrap();
        let error = reply.get_result().unwrap().get_error().unwrap();
        (error, reply.get_hold().ok())
    }
}

