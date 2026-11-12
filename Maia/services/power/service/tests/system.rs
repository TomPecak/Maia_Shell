//! The real system backend (system/) against stand-ins of the system's services on a private bus.
//!
//! Each test starts its own dbus-daemon and puts on it, from one connection: UPower (the manager, a
//! laptop battery, the display device, a mouse, the keyboard backlight), power-profiles-daemon and
//! logind's session (SetBrightness writes into a sysfs directory of the test, as the kernel would).
//! The service talks to them exactly as to the real ones: D-Bus calls, property signals, owners
//! coming and going. Nothing reaches the machine.

mod common;

use std::collections::HashMap;
use std::io::BufRead;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

use tokio::sync::mpsc;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Str};
use zbus::{Connection, connection};

use maia_power::power_capnp as p;
use maia_power::rpc::{Hub, PowerService};
use maia_power::system;

use common::{Client, connect, local};

const UPOWER: &str = "/org/freedesktop/UPower";
const BAT0: &str = "/org/freedesktop/UPower/devices/battery_BAT0";
const DISPLAY_DEVICE: &str = "/org/freedesktop/UPower/devices/DisplayDevice";
const MOUSE: &str = "/org/freedesktop/UPower/devices/mouse_dev_01";

// --- The stand-ins ---

struct FakeUPower {
    on_battery: bool,
    devices: Vec<String>,
}

#[zbus::interface(name = "org.freedesktop.UPower")]
impl FakeUPower {
    #[zbus(property)]
    fn on_battery(&self) -> bool {
        self.on_battery
    }

    #[zbus(property)]
    fn lid_is_present(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn lid_is_closed(&self) -> bool {
        false
    }

    fn enumerate_devices(&self) -> Vec<OwnedObjectPath> {
        self.devices.iter().map(|p| OwnedObjectPath::try_from(p.as_str()).unwrap()).collect()
    }

    fn get_display_device(&self) -> OwnedObjectPath {
        OwnedObjectPath::try_from(DISPLAY_DEVICE).unwrap()
    }

    #[zbus(signal)]
    async fn device_added(emitter: &SignalEmitter<'_>, device: OwnedObjectPath) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn device_removed(emitter: &SignalEmitter<'_>, device: OwnedObjectPath) -> zbus::Result<()>;
}

#[derive(Clone)]
struct FakeDevice {
    kind: u32,
    power_supply: bool,
    percentage: f64,
    state: u32,
    warning_level: u32,
    model: String,
}

#[zbus::interface(name = "org.freedesktop.UPower.Device")]
impl FakeDevice {
    #[zbus(property, name = "Type")]
    fn kind(&self) -> u32 {
        self.kind
    }

    #[zbus(property)]
    fn power_supply(&self) -> bool {
        self.power_supply
    }

    #[zbus(property)]
    fn is_present(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn percentage(&self) -> f64 {
        self.percentage
    }

    #[zbus(property)]
    fn state(&self) -> u32 {
        self.state
    }

    #[zbus(property)]
    fn warning_level(&self) -> u32 {
        self.warning_level
    }

    #[zbus(property)]
    fn time_to_empty(&self) -> i64 {
        if self.state == 2 { 7200 } else { 0 }
    }

    #[zbus(property)]
    fn time_to_full(&self) -> i64 {
        0
    }

    #[zbus(property)]
    fn energy_rate(&self) -> f64 {
        7.0
    }

    #[zbus(property)]
    fn capacity(&self) -> f64 {
        90.0
    }

    #[zbus(property)]
    fn vendor(&self) -> String {
        "Test".into()
    }

    #[zbus(property)]
    fn model(&self) -> String {
        self.model.clone()
    }

    #[zbus(property)]
    fn icon_name(&self) -> String {
        String::new()
    }
}

struct FakeKeyboard {
    value: i32,
}

#[zbus::interface(name = "org.freedesktop.UPower.KbdBacklight")]
impl FakeKeyboard {
    fn get_max_brightness(&self) -> i32 {
        3
    }

    fn get_brightness(&self) -> i32 {
        self.value
    }

    async fn set_brightness(&mut self, value: i32, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        self.value = value;
        let _ = Self::brightness_changed(&emitter, value).await;
    }

    #[zbus(signal)]
    async fn brightness_changed(emitter: &SignalEmitter<'_>, value: i32) -> zbus::Result<()>;
}

type Dict = HashMap<String, OwnedValue>;

fn text(value: &str) -> OwnedValue {
    OwnedValue::from(Str::from(value.to_string()))
}

#[derive(Default)]
struct ProfilesState {
    chosen: String,
    holds: Vec<(u32, String, String, String)>,
    next: u32,
}

/// power-profiles-daemon; `slow` makes setting a profile take a second, as an open polkit dialog
/// would. Its state is behind a mutex so that its methods take &self: zbus then runs them side by side.
struct FakeProfiles {
    state: std::sync::Mutex<ProfilesState>,
    slow: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl FakeProfiles {
    fn new(slow: std::sync::Arc<std::sync::atomic::AtomicBool>) -> FakeProfiles {
        FakeProfiles { state: std::sync::Mutex::new(ProfilesState { chosen: "balanced".into(), ..Default::default() }), slow }
    }

    fn active(&self) -> String {
        let state = self.state.lock().unwrap();
        if state.holds.iter().any(|h| h.1 == "power-saver") {
            "power-saver".into()
        } else if state.holds.iter().any(|h| h.1 == "performance") {
            "performance".into()
        } else {
            state.chosen.clone()
        }
    }
}

#[zbus::interface(name = "org.freedesktop.UPower.PowerProfiles")]
impl FakeProfiles {
    #[zbus(property)]
    fn active_profile(&self) -> String {
        self.active()
    }

    #[zbus(property)]
    async fn set_active_profile(&self, profile: String) {
        if self.slow.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        let mut state = self.state.lock().unwrap();
        state.chosen = profile;
        state.holds.clear();
    }

    #[zbus(property)]
    fn profiles(&self) -> Vec<Dict> {
        ["power-saver", "balanced", "performance"]
            .iter()
            .map(|p| HashMap::from([("Profile".to_string(), text(p)), ("Driver".to_string(), text("test"))]))
            .collect()
    }

    #[zbus(property)]
    fn performance_degraded(&self) -> String {
        String::new()
    }

    #[zbus(property)]
    fn active_profile_holds(&self) -> Vec<Dict> {
        self.state
            .lock()
            .unwrap()
            .holds
            .iter()
            .map(|(_, profile, reason, app)| {
                HashMap::from([
                    ("Profile".to_string(), text(profile)),
                    ("Reason".to_string(), text(reason)),
                    ("ApplicationId".to_string(), text(app)),
                ])
            })
            .collect()
    }

    async fn hold_profile(
        &self,
        profile: String,
        reason: String,
        application_id: String,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> u32 {
        let cookie = {
            let mut state = self.state.lock().unwrap();
            state.next += 1;
            let cookie = state.next;
            state.holds.push((cookie, profile, reason, application_id));
            cookie
        };
        let _ = self.active_profile_changed(&emitter).await;
        let _ = self.active_profile_holds_changed(&emitter).await;
        cookie
    }

    async fn release_profile(&self, cookie: u32, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) {
        self.state.lock().unwrap().holds.retain(|h| h.0 != cookie);
        let _ = self.active_profile_changed(&emitter).await;
        let _ = self.active_profile_holds_changed(&emitter).await;
    }
}

/// logind's session: SetBrightness writes the attribute, as logind does for the active session
struct FakeSession {
    sysfs: PathBuf,
    refuse: bool,
}

#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl FakeSession {
    fn set_brightness(&self, subsystem: String, name: String, value: u32) -> zbus::fdo::Result<()> {
        if self.refuse {
            return Err(zbus::fdo::Error::AccessDenied("not the active session".into()));
        }
        assert_eq!(subsystem, "backlight");
        std::fs::write(self.sysfs.join("class/backlight").join(name).join("brightness"), value.to_string())
            .map_err(|e| zbus::fdo::Error::Failed(e.to_string()))
    }
}

// --- A private bus with the stand-ins ---

static NEXT: AtomicU32 = AtomicU32::new(0);

struct Machine {
    daemon: Child,
    address: String,
    sysfs: PathBuf,
}

impl Drop for Machine {
    fn drop(&mut self) {
        let _ = self.daemon.kill();
        let _ = self.daemon.wait();
        let _ = std::fs::remove_dir_all(&self.sysfs);
    }
}

fn machine() -> Machine {
    let mut daemon = Command::new("dbus-daemon")
        .args(["--session", "--nofork", "--print-address=1"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("dbus-daemon");
    let mut address = String::new();
    std::io::BufReader::new(daemon.stdout.take().unwrap()).read_line(&mut address).unwrap();
    let sysfs = std::env::temp_dir().join(format!("maia-power-system-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
    let dir = sysfs.join("class/backlight/intel_backlight");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("type"), "raw\n").unwrap();
    std::fs::write(dir.join("max_brightness"), "1000\n").unwrap();
    std::fs::write(dir.join("brightness"), "500\n").unwrap();
    Machine { daemon, address: address.trim().to_string(), sysfs }
}

async fn bus(address: &str) -> Connection {
    connection::Builder::address(address).unwrap().build().await.unwrap()
}

fn laptop_battery(percentage: f64, state: u32, warning_level: u32) -> FakeDevice {
    FakeDevice { kind: 2, power_supply: true, percentage, state, warning_level, model: "BAT".into() }
}

/// Puts the stand-ins on the bus; `with_profiles`: power-profiles-daemon runs
async fn services(machine: &Machine, with_profiles: bool, refuse_brightness: bool) -> Connection {
    let conn = bus(&machine.address).await;
    let server = conn.object_server();
    server.at(UPOWER, FakeUPower { on_battery: true, devices: vec![BAT0.into(), MOUSE.into()] }).await.unwrap();
    server.at(BAT0, laptop_battery(83.0, 2, 1)).await.unwrap();
    server.at(DISPLAY_DEVICE, laptop_battery(83.0, 2, 1)).await.unwrap();
    server
        .at(MOUSE, FakeDevice { kind: 5, power_supply: false, percentage: 60.0, state: 2, warning_level: 1, model: "Mouse".into() })
        .await
        .unwrap();
    server.at("/org/freedesktop/UPower/KbdBacklight", FakeKeyboard { value: 1 }).await.unwrap();
    server
        .at("/org/freedesktop/login1/session/auto", FakeSession { sysfs: machine.sysfs.clone(), refuse: refuse_brightness })
        .await
        .unwrap();
    conn.request_name("org.freedesktop.UPower").await.unwrap();
    conn.request_name("org.freedesktop.login1").await.unwrap();
    if with_profiles {
        server.at("/org/freedesktop/UPower/PowerProfiles", FakeProfiles::new(Default::default())).await.unwrap();
        conn.request_name("org.freedesktop.UPower.PowerProfiles").await.unwrap();
    }
    conn
}

/// The service with the real system backend on the private bus and the test's sysfs
async fn service(machine: &Machine) -> Client {
    let conn = bus(&machine.address).await;
    let (events_tx, events_rx) = mpsc::unbounded_channel();
    let (commands, receivers) = system::channels();
    let hub = Hub::new();
    tokio::task::spawn_local(Hub::run(hub.clone(), events_rx));
    tokio::task::spawn_local(system::run_with(Some(conn), machine.sysfs.clone(), events_tx, receivers));
    connect(PowerService::client(hub, commands, system::NAME)).await
}

async fn change_device(conn: &Connection, path: &str, change: impl FnOnce(&mut FakeDevice)) {
    let iface = conn.object_server().interface::<_, FakeDevice>(path).await.unwrap();
    change(&mut *iface.get_mut().await);
    iface.get().await.percentage_changed(iface.signal_emitter()).await.unwrap();
}

fn raw_brightness(sysfs: &Path) -> String {
    std::fs::read_to_string(sysfs.join("class/backlight/intel_backlight/brightness")).unwrap().trim().to_string()
}

// --- The tests ---

#[test]
fn the_machine_as_upower_sysfs_and_ppd_tell_it() {
    let machine = machine();
    local(async {
        let _services = services(&machine, true, false).await;
        let client = service(&machine).await;
        client
            .wait("everything", |s| {
                s.batteries.len() == 2 && s.displays.contains_key("backlight:intel_backlight") && s.offered.len() == 3
                    && s.keyboard.is_some_and(|k| k.0)
            })
            .await;
        let s = client.seen.borrow();
        assert!(s.on_battery);
        assert_eq!(s.summary_percentage, 83.0);
        assert_eq!(s.batteries["battery_BAT0"].0, p::DeviceKind::Battery);
        assert_eq!(s.batteries["mouse_dev_01"], (p::DeviceKind::Mouse, 60.0));
        assert_eq!(s.displays["backlight:intel_backlight"].1, 500);
        assert_eq!(s.displays["backlight:intel_backlight"].2, 1000);
        assert_eq!(s.keyboard, Some((true, 1.0 / 3.0)));
        assert_eq!(s.active_profile, Some(p::Profile::Balanced));
    });
}

#[test]
fn brightness_goes_through_logind_and_comes_back_from_sysfs() {
    let machine = machine();
    local(async {
        let _services = services(&machine, true, false).await;
        let client = service(&machine).await;
        client.wait("the panel", |s| s.displays.contains_key("backlight:intel_backlight")).await;

        assert_eq!(client.set_brightness("", 0.8).await, p::ErrorCode::None);
        assert_eq!(raw_brightness(&machine.sysfs), "800");
        client.wait("80 %", |s| s.displays["backlight:intel_backlight"].1 == 800).await;

        // Changed by someone else (the keys through powerdevil): seen within a poll
        std::fs::write(machine.sysfs.join("class/backlight/intel_backlight/brightness"), "300\n").unwrap();
        client.wait("30 %", |s| s.displays["backlight:intel_backlight"].1 == 300).await;

        assert_eq!(client.step_brightness(1).await, p::ErrorCode::None);
        assert_eq!(raw_brightness(&machine.sysfs), "350");
    });
}

#[test]
fn a_session_in_the_background_may_not_change_the_screen() {
    let machine = machine();
    // The attribute is read-only for this user, as on most systems
    let attribute = machine.sysfs.join("class/backlight/intel_backlight/brightness");
    local(async {
        let _services = services(&machine, true, true).await;
        let client = service(&machine).await;
        client.wait("the panel", |s| s.displays.contains_key("backlight:intel_backlight")).await;
        let mut permissions = std::fs::metadata(&attribute).unwrap().permissions();
        std::os::unix::fs::PermissionsExt::set_mode(&mut permissions, 0o444);
        std::fs::set_permissions(&attribute, permissions).unwrap();
        // Root may write anyway; the check is only meaningful for a user
        if unsafe { libc::geteuid() } != 0 {
            assert_eq!(client.set_brightness("", 0.2).await, p::ErrorCode::NotAllowed);
            assert_eq!(raw_brightness(&machine.sysfs), "500");
        }
    });
}

#[test]
fn upower_signals_bring_the_charger_and_the_warnings() {
    let machine = machine();
    local(async {
        let services = services(&machine, true, false).await;
        let client = service(&machine).await;
        client.wait("the battery", |s| s.summary_percentage == 83.0).await;

        // Down to the low level
        for path in [BAT0, DISPLAY_DEVICE] {
            change_device(&services, path, |d| {
                d.percentage = 15.0;
                d.warning_level = 3;
            })
            .await;
        }
        client.wait("low", |s| s.events.iter().any(|e| e.0 == p::EventKind::BatteryLow)).await;

        // The charger
        let upower = services.object_server().interface::<_, FakeUPower>(UPOWER).await.unwrap();
        upower.get_mut().await.on_battery = false;
        upower.get().await.on_battery_changed(upower.signal_emitter()).await.unwrap();
        client.wait("charging", |s| s.events.iter().any(|e| e.0 == p::EventKind::ChargerConnected) && !s.on_battery).await;

        // A device appears and goes
        services
            .object_server()
            .at("/org/freedesktop/UPower/devices/headset_1", FakeDevice {
                kind: 17,
                power_supply: false,
                percentage: 30.0,
                state: 2,
                warning_level: 1,
                model: "Headset".into(),
            })
            .await
            .unwrap();
        upower.get_mut().await.devices.push("/org/freedesktop/UPower/devices/headset_1".into());
        FakeUPower::device_added(upower.signal_emitter(), OwnedObjectPath::try_from("/org/freedesktop/UPower/devices/headset_1").unwrap())
            .await
            .unwrap();
        client.wait("the headset", |s| s.batteries.get("headset_1").is_some_and(|b| b.0 == p::DeviceKind::Headset)).await;
        upower.get_mut().await.devices.retain(|d| !d.ends_with("headset_1"));
        FakeUPower::device_removed(upower.signal_emitter(), OwnedObjectPath::try_from("/org/freedesktop/UPower/devices/headset_1").unwrap())
            .await
            .unwrap();
        client.wait("gone", |s| !s.batteries.contains_key("headset_1")).await;
    });
}

#[test]
fn the_keyboard_backlight_through_upower() {
    let machine = machine();
    local(async {
        let _services = services(&machine, true, false).await;
        let client = service(&machine).await;
        client.wait("the keyboard", |s| s.keyboard.is_some_and(|k| k.0)).await;
        assert_eq!(client.set_keyboard(1.0).await, p::ErrorCode::None);
        client.wait("bright", |s| s.keyboard == Some((true, 1.0))).await;
    });
}

#[test]
fn profiles_and_holds_through_the_daemon() {
    let machine = machine();
    local(async {
        let services = services(&machine, true, false).await;
        let client = service(&machine).await;
        client.wait("the profiles", |s| s.offered.len() == 3).await;

        assert_eq!(client.set_profile(p::Profile::PowerSaver).await, p::ErrorCode::None);
        client.wait("power saver", |s| s.active_profile == Some(p::Profile::PowerSaver)).await;

        let (error, hold) = client.hold_profile(p::Profile::Performance, "Compiling").await;
        assert_eq!(error, p::ErrorCode::None);
        client.wait("held", |s| s.active_profile == Some(p::Profile::Performance) && s.holds == ["Compiling"]).await;
        drop(hold);
        client.wait("released", |s| s.active_profile == Some(p::Profile::PowerSaver) && s.holds.is_empty()).await;

        // The daemon goes away: profiles are unavailable, and come back with it
        services.release_name("org.freedesktop.UPower.PowerProfiles").await.unwrap();
        client.wait("unavailable", |s| s.offered.is_empty()).await;
        assert_eq!(client.set_profile(p::Profile::Balanced).await, p::ErrorCode::Unavailable);
        services.request_name("org.freedesktop.UPower.PowerProfiles").await.unwrap();
        client.wait("back", |s| s.offered.len() == 3).await;
    });
}

#[test]
fn without_power_profiles_daemon() {
    let machine = machine();
    local(async {
        let _services = services(&machine, false, false).await;
        let client = service(&machine).await;
        client.wait("the battery", |s| s.summary_percentage == 83.0).await;
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(client.seen.borrow().offered.is_empty());
        assert_eq!(client.set_profile(p::Profile::Performance).await, p::ErrorCode::Unavailable);
    });
}

#[test]
fn without_upower() {
    let machine = machine();
    local(async {
        // Nothing on the bus: no UPower, no daemon; the backlight still works through sysfs
        let client = service(&machine).await;
        client.wait("the panel", |s| s.displays.contains_key("backlight:intel_backlight")).await;
        tokio::time::sleep(Duration::from_millis(100)).await;
        let s = client.seen.borrow();
        assert!(s.batteries.is_empty());
        assert_eq!(s.keyboard, Some((false, 0.0)));
    });
}

#[test]
fn a_profile_change_waiting_for_a_password_holds_nothing_else_up() {
    let machine = machine();
    local(async {
        let services = services(&machine, true, false).await;
        let client = std::rc::Rc::new(service(&machine).await);
        client.wait("the profiles", |s| s.offered.len() == 3).await;
        let profiles = services.object_server().interface::<_, FakeProfiles>("/org/freedesktop/UPower/PowerProfiles").await.unwrap();
        profiles.get().await.slow.store(true, Ordering::SeqCst);

        // The change waits a second, as for the administrator's password
        let started = std::time::Instant::now();
        let slow = {
            let client = client.clone();
            tokio::task::spawn_local(async move { client.set_profile(p::Profile::Performance).await })
        };
        tokio::time::sleep(Duration::from_millis(100)).await;
        // Meanwhile a hold is made and seen at once
        let (error, _hold) = client.hold_profile(p::Profile::PowerSaver, "Presenting").await;
        assert_eq!(error, p::ErrorCode::None);
        client.wait("held", |s| s.active_profile == Some(p::Profile::PowerSaver)).await;
        assert!(started.elapsed() < Duration::from_millis(800), "the hold waited for the change: {:?}", started.elapsed());

        assert_eq!(slow.await.unwrap(), p::ErrorCode::None);
        assert!(started.elapsed() >= Duration::from_secs(1));
        // Choosing by hand released the hold, as the daemon does
        client.wait("performance", |s| s.active_profile == Some(p::Profile::Performance) && s.holds.is_empty()).await;
    });
}
