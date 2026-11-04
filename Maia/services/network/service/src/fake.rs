//! A simulated NetworkManager: one Wi-Fi adapter, a handful of networks and a saved home network.
//!
//! For the tests of the service and for working on the user interface in a nested session without
//! touching the real network of the machine (MAIA_NETWORK_BACKEND=fake). It behaves like the real
//! thing where it matters for the interface:
//!
//! - connecting takes a moment (`Timing::step`) and goes disconnected -> connecting -> connected;
//! - a new secured network asks for its password through the prompter; the password
//!   "wrong-password" is refused (state failed, reason wrongSecrets), cancelling ends with noSecrets
//!   and the new profile is removed again;
//! - "Hotel Guest" is a captive portal until checkConnectivity() (the user signed in);
//! - scanning takes a moment and moves the signal strengths a little;
//! - Wi-Fi off empties the list; on again, the home network connects by itself;
//! - the hotspot replaces the Wi-Fi connection while it runs.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::rc::Rc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tokio::sync::mpsc;

use crate::backend::{BackendEvent, Command, ErrorCode, HotspotPassword, OpError, OpResult};
use crate::model::{
    AccessPoint, BAND_2_4_GHZ, BAND_5_GHZ, ConnectionType, Connectivity, DeviceState, Event, IpAddress, IpInfo, Metered,
    Permission, Permissions, PrimaryConnection, SavedConnection, Security, StateReason, Status, WifiDevice, WifiMode,
};
use crate::prompt::Prompter;
use crate::settings::{ConnectionSettings, IpMethod, Secret, SecretKey, SecretReply, SecretRequest, find_secret, secret_fields};

pub const NAME: &str = "fake";

const DEVICE: &str = "wlan0";
const HOME_UUID: &str = "5f1d4c3e-0000-4000-8000-000000000001";
const HOME_PASSWORD: &str = "maia-home";
const WRONG_PASSWORD: &str = "wrong-password";
const PORTAL_SSID: &[u8] = b"Hotel Guest";

/// How long the simulated steps take
#[derive(Clone, Copy, Debug)]
pub struct Timing {
    pub step: Duration,
}

impl Timing {
    /// Like a real adapter, for working on the interface
    pub fn realistic() -> Self {
        Timing { step: Duration::from_millis(900) }
    }

    /// For tests
    pub fn fast() -> Self {
        Timing { step: Duration::from_millis(20) }
    }
}

struct Profile {
    connection: SavedConnection,
    settings: ConnectionSettings,
    secrets: Vec<Secret>,
}

struct State {
    events: mpsc::UnboundedSender<BackendEvent>,
    prompter: Prompter,
    timing: Timing,
    status: Status,
    device: WifiDevice,
    access_points: Vec<AccessPoint>,
    profiles: BTreeMap<String, Profile>,
    portal_signed_in: bool,
    /// Bumped by every new activation, so a late step of an older one does nothing
    attempt: u64,
    next_request: u64,
}

type StateRef = Rc<RefCell<State>>;

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn ap(bssid: &str, ssid: &str, security: Security, strength: u8, frequency: u32) -> AccessPoint {
    AccessPoint {
        bssid: bssid.into(),
        ssid: ssid.as_bytes().to_vec(),
        security,
        mode: WifiMode::Infrastructure,
        strength,
        frequency,
        max_bitrate: if frequency > 5000 { 866_000 } else { 144_000 },
        last_seen: now_ms(),
    }
}

fn visible_access_points() -> Vec<AccessPoint> {
    vec![
        ap("0A:00:00:00:00:01", "Maia Home", Security::WpaPersonal, 82, 5180),
        ap("0A:00:00:00:00:02", "Maia Home", Security::WpaPersonal, 64, 2437),
        ap("0A:00:00:00:00:03", "Cafe Lumen", Security::None, 55, 2412),
        ap("0A:00:00:00:00:04", "Office", Security::WpaEnterprise, 48, 5240),
        ap("0A:00:00:00:00:05", "Neighbour 5G", Security::Wpa3Personal, 37, 5500),
        ap("0A:00:00:00:00:06", "Hotel Guest", Security::None, 41, 2462),
        ap("0A:00:00:00:00:07", "Far Away", Security::WpaPersonal, 12, 2472),
        ap("0A:00:00:00:00:08", "", Security::WpaPersonal, 30, 2442),
    ]
}

fn profile_for(uuid: &str, ssid: &[u8], security: Security, secrets: Vec<Secret>) -> Profile {
    let name = String::from_utf8_lossy(ssid).into_owned();
    let mut settings = ConnectionSettings { name: name.clone(), ..Default::default() };
    settings.wifi.ssid = ssid.to_vec();
    settings.security.security = security;
    settings.ip6.method = IpMethod::Auto;
    Profile {
        connection: SavedConnection {
            uuid: uuid.into(),
            name,
            ssid: ssid.to_vec(),
            security,
            autoconnect: true,
            metered: Metered::Unknown,
            ..Default::default()
        },
        settings,
        secrets,
    }
}

impl State {
    fn send(&self, event: BackendEvent) {
        let _ = self.events.send(event);
    }

    fn publish_status(&self) {
        self.send(BackendEvent::Status(self.status.clone()));
    }

    fn publish_device(&self) {
        self.send(BackendEvent::Device(self.device.clone()));
    }

    fn publish_access_points(&self) {
        self.send(BackendEvent::AccessPoints { device_id: DEVICE.into(), access_points: self.access_points.clone() });
    }

    fn publish_profile(&self, uuid: &str) {
        if let Some(profile) = self.profiles.get(uuid) {
            self.send(BackendEvent::Connection(profile.connection.clone()));
        }
    }

    fn set_device(&mut self, state: DeviceState, reason: StateReason) {
        self.device.state = state;
        self.device.state_reason = reason;
    }

    /// The device and status of "not connected"
    fn disconnected(&mut self, reason: StateReason) {
        if let Some(profile) = self.profiles.get_mut(&self.device.active_connection_uuid) {
            profile.connection.active_device_id.clear();
        }
        let previous = std::mem::take(&mut self.device.active_connection_uuid);
        self.device.active_ssid.clear();
        self.device.hotspot = false;
        self.device.bitrate = 0;
        self.device.ip4 = IpInfo::default();
        self.device.ip6 = IpInfo::default();
        let state = if self.status.wireless_enabled { DeviceState::Disconnected } else { DeviceState::Unavailable };
        self.set_device(state, reason);
        self.status.connectivity = Connectivity::None;
        self.status.primary = PrimaryConnection::default();
        self.publish_profile(&previous);
    }
}

pub async fn run(events: mpsc::UnboundedSender<BackendEvent>, mut commands: mpsc::UnboundedReceiver<Command>, prompter: Prompter, timing: Timing) {
    let all = Permission::Yes;
    let state = Rc::new(RefCell::new(State {
        events,
        prompter,
        timing,
        status: Status {
            running: true,
            networking_enabled: true,
            wireless_enabled: true,
            wireless_hardware_enabled: true,
            connectivity: Connectivity::None,
            connectivity_check_uri: "http://nmcheck.gnome.org/check_network_status.txt".into(),
            primary: PrimaryConnection::default(),
            permissions: Permissions {
                enable_disable_wifi: all,
                network_control: all,
                modify_own: all,
                modify_system: all,
                wifi_share_open: all,
                wifi_share_protected: all,
            },
        },
        device: WifiDevice {
            id: DEVICE.into(),
            hw_address: "52:54:00:12:34:56".into(),
            perm_hw_address: "52:54:00:12:34:56".into(),
            state: DeviceState::Disconnected,
            bands: BAND_2_4_GHZ | BAND_5_GHZ,
            can_hotspot: true,
            last_scan: now_ms(),
            ..Default::default()
        },
        access_points: visible_access_points(),
        profiles: BTreeMap::new(),
        portal_signed_in: false,
        attempt: 0,
        next_request: 0,
    }));
    {
        let mut s = state.borrow_mut();
        let mut home = profile_for(
            HOME_UUID,
            b"Maia Home",
            Security::WpaPersonal,
            vec![Secret { key: SecretKey::WifiPassword, value: HOME_PASSWORD.into() }],
        );
        home.connection.last_used = now_ms() - 86_400_000;
        s.profiles.insert(HOME_UUID.into(), home);
        s.publish_profile(HOME_UUID);
        s.publish_status();
        s.publish_device();
        s.publish_access_points();
    }
    // Like an autoconnecting profile at login
    tokio::task::spawn_local(activate(state.clone(), HOME_UUID.into(), false));

    while let Some(command) = commands.recv().await {
        handle(&state, command);
    }
}

fn handle(state: &StateRef, command: Command) {
    match command {
        Command::SetWirelessEnabled { enabled, reply } => {
            let _ = reply.send(set_wireless(state, enabled));
        }
        Command::RequestScan { device_id, reply } => {
            let result = check_device(&device_id).and_then(|()| {
                let s = state.borrow();
                if s.status.wireless_enabled { Ok(()) } else { Err(OpError::new(ErrorCode::Unavailable, "Wi-Fi is off")) }
            });
            if result.is_ok() {
                tokio::task::spawn_local(scan(state.clone()));
            }
            let _ = reply.send(result);
        }
        Command::ConnectNetwork { device_id, ssid, security, connection_uuid, reply, .. } => {
            let result = check_device(&device_id).and_then(|()| check_enabled(state));
            if result.is_ok() {
                match connection_uuid {
                    Some(uuid) => {
                        tokio::task::spawn_local(activate(state.clone(), uuid, false));
                    }
                    None => {
                        let uuid = uuid::Uuid::new_v4().to_string();
                        state.borrow_mut().profiles.insert(uuid.clone(), profile_for(&uuid, &ssid, security, Vec::new()));
                        state.borrow().publish_profile(&uuid);
                        tokio::task::spawn_local(activate(state.clone(), uuid, true));
                    }
                }
            }
            let _ = reply.send(result);
        }
        Command::Activate { uuid, device_id, reply } => {
            let result = check_device(&device_id).and_then(|()| check_enabled(state)).and_then(|()| {
                if state.borrow().profiles.contains_key(&uuid) {
                    Ok(())
                } else {
                    Err(OpError::new(ErrorCode::NotFound, format!("no connection {uuid}")))
                }
            });
            if result.is_ok() {
                tokio::task::spawn_local(activate(state.clone(), uuid, false));
            }
            let _ = reply.send(result);
        }
        Command::ConnectWithSettings { device_id, settings, secrets, reply } => {
            let result = check_device(&device_id).and_then(|()| check_enabled(state)).and_then(|()| {
                if settings.wifi.ssid.is_empty() || settings.wifi.ssid.len() > 32 {
                    return Err(OpError::new(ErrorCode::InvalidArgument, "the SSID must have 1 to 32 bytes"));
                }
                let uuid = uuid::Uuid::new_v4().to_string();
                let mut profile = profile_for(&uuid, &settings.wifi.ssid, settings.security.security, secrets);
                profile.connection.hidden = settings.wifi.hidden;
                profile.settings = ConnectionSettings { name: profile.connection.name.clone(), ..settings };
                state.borrow_mut().profiles.insert(uuid.clone(), profile);
                state.borrow().publish_profile(&uuid);
                tokio::task::spawn_local(activate(state.clone(), uuid.clone(), true));
                Ok(uuid)
            });
            let _ = reply.send(result);
        }
        Command::Disconnect { device_id, reply } => {
            let result = check_device(&device_id);
            if result.is_ok() {
                let mut s = state.borrow_mut();
                s.attempt += 1;
                s.disconnected(StateReason::UserRequested);
                s.publish_status();
                s.publish_device();
            }
            let _ = reply.send(result);
        }
        Command::Forget { uuid, reply } => {
            let mut s = state.borrow_mut();
            let result = if s.profiles.remove(&uuid).is_some() {
                if s.device.active_connection_uuid == uuid {
                    s.attempt += 1;
                    s.disconnected(StateReason::ConnectionRemoved);
                    s.publish_status();
                    s.publish_device();
                }
                s.send(BackendEvent::ConnectionRemoved(uuid));
                Ok(())
            } else {
                Err(OpError::new(ErrorCode::NotFound, format!("no connection {uuid}")))
            };
            let _ = reply.send(result);
        }
        Command::Settings { uuid, reply } => {
            let s = state.borrow();
            let result = s
                .profiles
                .get(&uuid)
                .map(|p| {
                    let mut settings = p.settings.clone();
                    settings.autoconnect = p.connection.autoconnect;
                    settings.metered = p.connection.metered;
                    settings.available_to_all = p.connection.available_to_all;
                    settings
                })
                .ok_or_else(|| OpError::new(ErrorCode::NotFound, format!("no connection {uuid}")));
            let _ = reply.send(result);
        }
        Command::UpdateSettings { uuid, settings, secrets, reply } => {
            let mut s = state.borrow_mut();
            let result = match s.profiles.get_mut(&uuid) {
                Some(profile) => {
                    profile.connection.name = settings.name.clone();
                    profile.connection.autoconnect = settings.autoconnect;
                    profile.connection.metered = settings.metered;
                    profile.connection.available_to_all = settings.available_to_all;
                    profile.connection.hidden = settings.wifi.hidden;
                    profile.settings = settings;
                    for secret in secrets {
                        profile.secrets.retain(|s| s.key != secret.key);
                        profile.secrets.push(secret);
                    }
                    Ok(())
                }
                None => Err(OpError::new(ErrorCode::NotFound, format!("no connection {uuid}"))),
            };
            if result.is_ok() {
                s.publish_profile(&uuid);
            }
            let _ = reply.send(result);
        }
        Command::Secrets { uuid, reply } => {
            let s = state.borrow();
            let result = s
                .profiles
                .get(&uuid)
                .map(|p| p.secrets.clone())
                .ok_or_else(|| OpError::new(ErrorCode::NotFound, format!("no connection {uuid}")));
            let _ = reply.send(result);
        }
        Command::StartHotspot { device_id, ssid, password, reply } => {
            let result = check_device(&device_id).and_then(|()| check_enabled(state)).map(|()| start_hotspot(state, ssid, password));
            let _ = reply.send(result);
        }
        Command::StopHotspot { device_id, reply } => {
            let result = check_device(&device_id).and_then(|()| {
                let mut s = state.borrow_mut();
                if !s.device.hotspot {
                    return Err(OpError::new(ErrorCode::NotFound, "no hotspot runs"));
                }
                s.attempt += 1;
                s.disconnected(StateReason::UserRequested);
                s.publish_status();
                s.publish_device();
                Ok(())
            });
            let _ = reply.send(result);
        }
        Command::CheckConnectivity { reply } => {
            let mut s = state.borrow_mut();
            if s.status.connectivity == Connectivity::Portal {
                s.portal_signed_in = true;
                s.status.connectivity = Connectivity::Full;
                s.publish_status();
            }
            let _ = reply.send(Ok(()));
        }
    }
}

fn check_device(device_id: &str) -> OpResult {
    if device_id.is_empty() || device_id == DEVICE {
        Ok(())
    } else {
        Err(OpError::new(ErrorCode::NotFound, format!("no device {device_id}")))
    }
}

fn check_enabled(state: &StateRef) -> OpResult {
    if state.borrow().status.wireless_enabled {
        Ok(())
    } else {
        Err(OpError::new(ErrorCode::Unavailable, "Wi-Fi is off"))
    }
}

fn set_wireless(state: &StateRef, enabled: bool) -> OpResult {
    let mut s = state.borrow_mut();
    if s.status.wireless_enabled == enabled {
        return Ok(());
    }
    s.status.wireless_enabled = enabled;
    s.attempt += 1;
    if enabled {
        s.access_points = visible_access_points();
        s.set_device(DeviceState::Disconnected, StateReason::None);
    } else {
        s.disconnected(StateReason::None);
        s.access_points.clear();
    }
    s.publish_status();
    s.publish_device();
    s.publish_access_points();
    if enabled {
        drop(s);
        tokio::task::spawn_local(activate(state.clone(), HOME_UUID.into(), false));
    }
    Ok(())
}

async fn scan(state: StateRef) {
    let step = {
        let mut s = state.borrow_mut();
        s.device.scanning = true;
        s.publish_device();
        s.timing.step
    };
    tokio::time::sleep(step).await;
    let mut s = state.borrow_mut();
    s.device.scanning = false;
    s.device.last_scan = now_ms();
    let seed = (s.device.last_scan / 1000) as u64;
    for (i, ap) in s.access_points.iter_mut().enumerate() {
        // A little movement, as signals do
        let delta = ((seed + i as u64 * 7) % 7) as i16 - 3;
        ap.strength = (ap.strength as i16 + delta).clamp(5, 99) as u8;
        ap.last_seen = now_ms();
    }
    s.publish_device();
    s.publish_access_points();
}

/// Activates a profile: connecting, maybe a password question, then connected or failed.
/// `new_profile`: made just now from a network; removed again when the user cancels.
async fn activate(state: StateRef, uuid: String, new_profile: bool) {
    let (attempt, step) = {
        let mut s = state.borrow_mut();
        let Some(profile) = s.profiles.get(&uuid) else { return };
        let ssid = profile.connection.ssid.clone();
        s.attempt += 1;
        let previous = std::mem::take(&mut s.device.active_connection_uuid);
        if let Some(old) = s.profiles.get_mut(&previous) {
            old.connection.active_device_id.clear();
        }
        s.publish_profile(&previous);
        s.device.hotspot = false;
        s.device.active_connection_uuid = uuid.clone();
        s.device.active_ssid = ssid.clone();
        s.set_device(DeviceState::Connecting, StateReason::None);
        s.status.primary = PrimaryConnection {
            kind: ConnectionType::Wifi,
            name: String::from_utf8_lossy(&ssid).into_owned(),
            uuid: uuid.clone(),
            device_id: DEVICE.into(),
            activating: true,
        };
        s.status.connectivity = Connectivity::None;
        s.publish_status();
        s.publish_device();
        (s.attempt, s.timing.step)
    };
    tokio::time::sleep(step).await;

    // Secrets: a secured profile without them asks the user
    let request = {
        let mut s = state.borrow_mut();
        if s.attempt != attempt {
            return;
        }
        let profile = &s.profiles[&uuid];
        let security = profile.connection.security;
        let name = profile.connection.name.clone();
        let fields = secret_fields(security, Some(profile.settings.security.eap.method), false);
        let missing = fields.iter().any(|f| find_secret(&profile.secrets, f.key).is_none());
        if fields.is_empty() || !missing {
            None
        } else {
            s.next_request += 1;
            let request = SecretRequest {
                id: format!("fake-{}", s.next_request),
                connection_uuid: uuid.clone(),
                name,
                device_id: DEVICE.into(),
                security,
                fields,
                retry: false,
                wps_push_button: false,
            };
            s.set_device(DeviceState::NeedAuth, StateReason::None);
            s.publish_device();
            Some((request, s.prompter.clone()))
        }
    };
    if let Some((request, prompter)) = request {
        let reply = prompter.ask(request).await;
        let mut s = state.borrow_mut();
        if s.attempt != attempt {
            return;
        }
        match reply {
            SecretReply::Cancelled => {
                fail(&mut s, &uuid, StateReason::NoSecrets);
                if new_profile {
                    s.profiles.remove(&uuid);
                    s.send(BackendEvent::ConnectionRemoved(uuid.clone()));
                }
                return;
            }
            SecretReply::Secrets(secrets) => {
                if let Some(profile) = s.profiles.get_mut(&uuid) {
                    profile.secrets = secrets;
                }
                s.set_device(DeviceState::Connecting, StateReason::None);
                s.publish_device();
            }
        }
    }
    tokio::time::sleep(step).await;

    let mut s = state.borrow_mut();
    if s.attempt != attempt {
        return;
    }
    let profile = &s.profiles[&uuid];
    if find_secret(&profile.secrets, SecretKey::WifiPassword) == Some(WRONG_PASSWORD) {
        if let Some(profile) = s.profiles.get_mut(&uuid) {
            profile.secrets.clear();
        }
        fail(&mut s, &uuid, StateReason::WrongSecrets);
        return;
    }
    let ssid = profile.connection.ssid.clone();
    let portal = ssid == PORTAL_SSID && !s.portal_signed_in;
    let frequency = s.access_points.iter().filter(|ap| ap.ssid == ssid).map(|ap| ap.frequency).next().unwrap_or(2412);
    if let Some(profile) = s.profiles.get_mut(&uuid) {
        profile.connection.active_device_id = DEVICE.into();
        profile.connection.last_used = now_ms();
    }
    s.set_device(DeviceState::Connected, StateReason::None);
    s.device.bitrate = if frequency > 5000 { 585_000 } else { 130_000 };
    s.device.ip4 = IpInfo {
        addresses: vec![IpAddress { address: "192.168.1.23".into(), prefix: 24 }],
        gateway: "192.168.1.1".into(),
        dns: vec!["192.168.1.1".into()],
    };
    s.device.ip6 = IpInfo {
        addresses: vec![IpAddress { address: "fe80::5054:ff:fe12:3456".into(), prefix: 64 }],
        gateway: String::new(),
        dns: Vec::new(),
    };
    s.status.primary.activating = false;
    s.status.connectivity = if portal { Connectivity::Portal } else { Connectivity::Full };
    s.publish_profile(&uuid);
    s.publish_status();
    s.publish_device();
    s.send(BackendEvent::Event(Event::Connected(uuid)));
}

fn fail(s: &mut State, uuid: &str, reason: StateReason) {
    let name = s.profiles.get(uuid).map(|p| p.connection.name.clone()).unwrap_or_default();
    s.disconnected(reason);
    s.set_device(DeviceState::Failed, reason);
    s.publish_status();
    s.publish_device();
    if reason != StateReason::NoSecrets {
        s.send(BackendEvent::Event(Event::ActivationFailed {
            device_id: DEVICE.into(),
            connection_uuid: uuid.into(),
            name,
            reason,
        }));
    }
}

fn start_hotspot(state: &StateRef, ssid: String, password: HotspotPassword) -> (String, String) {
    let mut s = state.borrow_mut();
    // As the NetworkManager backend: the hotspot profile keeps its password unless one is given
    let kept = s.profiles.values().find(|p| p.connection.hotspot).and_then(|p| find_secret(&p.secrets, SecretKey::WifiPassword));
    let password = match password {
        HotspotPassword::Given(password) => password,
        HotspotPassword::Generate => kept.map_or_else(|| "fq7Rk2Mw".to_string(), str::to_string),
    };
    let ssid = if ssid.is_empty() { "maia".to_string() } else { ssid };
    let uuid = s
        .profiles
        .values()
        .find(|p| p.connection.hotspot)
        .map(|p| p.connection.uuid.clone())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let mut profile =
        profile_for(&uuid, ssid.as_bytes(), Security::WpaPersonal, vec![Secret { key: SecretKey::WifiPassword, value: password.clone() }]);
    profile.connection.name = "Hotspot".into();
    profile.connection.hotspot = true;
    profile.connection.autoconnect = false;
    profile.connection.active_device_id = DEVICE.into();
    profile.settings.ip4.method = IpMethod::Shared;
    s.attempt += 1;
    s.disconnected(StateReason::None);
    s.profiles.insert(uuid.clone(), profile);
    s.device.hotspot = true;
    s.device.active_connection_uuid = uuid.clone();
    s.set_device(DeviceState::Connected, StateReason::None);
    s.status.primary = PrimaryConnection::default();
    s.publish_profile(&uuid);
    s.publish_status();
    s.publish_device();
    (uuid, password)
}
