//! The NetworkManager backend: D-Bus (system bus) through zbus, turned into `BackendEvent`s, and
//! `Command`s carried out as NetworkManager calls.
//!
//! How it follows NetworkManager: it listens to every signal NetworkManager sends (property changes
//! of the manager, devices, access points and active connections; new and removed profiles; device
//! state changes) and marks what they concern as dirty. Shortly after the first signal of a burst
//! (`SETTLE`), it reads the dirty objects again and sends their whole state. Reading whole objects
//! instead of applying single property changes keeps the backend simple and never out of step;
//! NetworkManager answers GetAll in well under a millisecond.
//!
//! Commands run as their own tasks, so a slow call (a polkit dialog) never holds up the state.
//! Calls that may need authorization allow interactive polkit authentication.
//!
//! Times: NetworkManager's LastScan and LastSeen count from boot (CLOCK_BOOTTIME); the model wants
//! ms since 1970.

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::net::Ipv6Addr;
use std::rc::Rc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use futures::StreamExt;
use tokio::sync::mpsc;
use zbus::message::Type as MessageType;
use zbus::proxy::MethodFlags;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, MatchRule, MessageStream, Proxy};

use crate::agent::{self, Agent};
use crate::backend::{BackendEvent, Command, ErrorCode, OpError, OpResult};
use crate::model::{
    AccessPoint, ConnectionType, Event, IpAddress, IpInfo, Metered, Permission, Permissions, PrimaryConnection,
    SavedConnection, Status, WifiDevice,
};
use crate::nmdefs;
use crate::prompt::Prompter;

pub const NAME: &str = "networkmanager";

const NM: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const IFACE_NM: &str = "org.freedesktop.NetworkManager";
const IFACE_DEVICE: &str = "org.freedesktop.NetworkManager.Device";
const IFACE_WIRELESS: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const IFACE_AP: &str = "org.freedesktop.NetworkManager.AccessPoint";
const IFACE_ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const IFACE_SETTINGS: &str = "org.freedesktop.NetworkManager.Settings";
const IFACE_CONNECTION: &str = "org.freedesktop.NetworkManager.Settings.Connection";
const IFACE_IP4: &str = "org.freedesktop.NetworkManager.IP4Config";
const IFACE_IP6: &str = "org.freedesktop.NetworkManager.IP6Config";
const IFACE_PROPERTIES: &str = "org.freedesktop.DBus.Properties";

/// How long a burst of signals may go on before the dirty objects are read
const SETTLE: Duration = Duration::from_millis(30);
/// A scan is over when LastScan changes; at the latest after this
const SCAN_TIMEOUT: Duration = Duration::from_secs(10);

type Props = HashMap<String, OwnedValue>;
type SettingsDict = HashMap<String, HashMap<String, OwnedValue>>;

// --- Reading values ---

fn u32_of(props: &Props, key: &str) -> u32 {
    props.get(key).and_then(|v| u32::try_from(&**v).ok()).unwrap_or(0)
}

fn i64_of(props: &Props, key: &str) -> i64 {
    props.get(key).and_then(|v| i64::try_from(&**v).ok()).unwrap_or(0)
}

fn bool_of(props: &Props, key: &str) -> bool {
    props.get(key).and_then(|v| bool::try_from(&**v).ok()).unwrap_or(false)
}

fn string_of(props: &Props, key: &str) -> String {
    props.get(key).and_then(|v| <&str>::try_from(&**v).ok()).map(str::to_string).unwrap_or_default()
}

fn path_of(props: &Props, key: &str) -> Option<OwnedObjectPath> {
    let path = props.get(key).and_then(|v| ObjectPath::try_from(&**v).ok()).map(OwnedObjectPath::from)?;
    (path.as_str() != "/").then_some(path)
}

fn owned<T: TryFrom<OwnedValue>>(props: &Props, key: &str) -> Option<T> {
    props.get(key).and_then(|v| v.try_clone().ok()).and_then(|v| T::try_from(v).ok())
}

fn paths_of(props: &Props, key: &str) -> Vec<OwnedObjectPath> {
    owned::<Vec<OwnedObjectPath>>(props, key).unwrap_or_default()
}

fn bytes_of(props: &Props, key: &str) -> Vec<u8> {
    owned::<Vec<u8>>(props, key).unwrap_or_default()
}

fn setting<'a>(dict: &'a SettingsDict, name: &str) -> Option<&'a Props> {
    dict.get(name)
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// Milliseconds since boot (CLOCK_BOOTTIME), the clock of LastScan and LastSeen
fn boottime_ms() -> i64 {
    let mut time = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: clock_gettime only writes the timespec it is given
    #[allow(unsafe_code)]
    let ok = unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut time) } == 0;
    if ok { time.tv_sec * 1000 + time.tv_nsec / 1_000_000 } else { 0 }
}

fn boot_to_epoch_ms(boot_ms: i64) -> i64 {
    if boot_ms <= 0 { 0 } else { now_ms() - (boottime_ms() - boot_ms) }
}

// --- D-Bus calls ---

async fn get_all(conn: &Connection, path: &ObjectPath<'_>, interface: &str) -> zbus::Result<Props> {
    let reply = conn.call_method(Some(NM), path, Some(IFACE_PROPERTIES), "GetAll", &(interface,)).await?;
    reply.body().deserialize::<Props>()
}

/// A method call that may ask polkit interactively
async fn call<B, R>(conn: &Connection, path: &str, interface: &str, method: &str, body: &B) -> OpResult<R>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
    R: for<'d> zbus::zvariant::DynamicDeserialize<'d>,
{
    let proxy = Proxy::new(conn, NM, path.to_string(), interface.to_string()).await.map_err(failed)?;
    proxy
        .call_with_flags::<_, B, R>(method, MethodFlags::AllowInteractiveAuth.into(), body)
        .await
        .map_err(failed)?
        .ok_or_else(|| OpError::new(ErrorCode::Failed, format!("{method}: no reply")))
}

fn failed(error: zbus::Error) -> OpError {
    let code = match &error {
        zbus::Error::MethodError(name, _, _) => {
            let name = name.as_str();
            if name.ends_with("PermissionDenied") || name.ends_with("AccessDenied") || name.contains("NotAuthorized") {
                ErrorCode::NotAllowed
            } else if name.ends_with("UnknownConnection") || name.ends_with("UnknownDevice") || name.ends_with("UnknownMethod") {
                ErrorCode::NotFound
            } else if name.ends_with("NotSoftwareEnabled") || name.ends_with("NotAvailable") {
                ErrorCode::Unavailable
            } else {
                ErrorCode::Failed
            }
        }
        _ => ErrorCode::Failed,
    };
    OpError::new(code, error.to_string())
}

// --- What the backend remembers between refreshes ---

struct DeviceEntry {
    device: WifiDevice,
    /// Access point paths and their last read state
    access_points: HashMap<OwnedObjectPath, AccessPoint>,
    active_connection_name: String,
    /// LastScan (boot ms) when a scan was requested, until it changes
    scan_requested: Option<(i64, Instant)>,
}

#[derive(Default)]
struct Dirty {
    status: bool,
    devices_list: bool,
    devices: HashSet<OwnedObjectPath>,
    access_points: HashSet<OwnedObjectPath>,
    connections: bool,
    permissions: bool,
}

impl Dirty {
    fn everything() -> Dirty {
        Dirty { status: true, devices_list: true, connections: true, permissions: true, ..Default::default() }
    }

    fn any(&self) -> bool {
        self.status
            || self.devices_list
            || self.connections
            || self.permissions
            || !self.devices.is_empty()
            || !self.access_points.is_empty()
    }
}

struct State {
    conn: Connection,
    events: mpsc::UnboundedSender<BackendEvent>,
    status: Status,
    devices: HashMap<OwnedObjectPath, DeviceEntry>,
    /// Access point path -> the device that sees it
    ap_owner: HashMap<OwnedObjectPath, OwnedObjectPath>,
    connections: HashMap<OwnedObjectPath, SavedConnection>,
    dirty: Dirty,
}

type StateRef = Rc<RefCell<State>>;

impl State {
    fn send(&self, event: BackendEvent) {
        let _ = self.events.send(event);
    }

    fn device_path(&self, id: &str) -> Option<OwnedObjectPath> {
        self.devices.iter().find(|(_, e)| e.device.id == id).map(|(p, _)| p.clone())
    }

    /// The interface a profile is active on, "" when it is not
    fn active_device_of(&self, uuid: &str) -> String {
        self.devices
            .values()
            .find(|e| e.device.active_connection_uuid == uuid)
            .map(|e| e.device.id.clone())
            .unwrap_or_default()
    }

    fn connection_path(&self, uuid: &str) -> Option<OwnedObjectPath> {
        self.connections.iter().find(|(_, c)| c.uuid == uuid).map(|(p, _)| p.clone())
    }

    fn access_point_path(&self, device: &OwnedObjectPath, bssid: &str) -> Option<OwnedObjectPath> {
        let entry = self.devices.get(device)?;
        entry.access_points.iter().find(|(_, ap)| ap.bssid == bssid).map(|(p, _)| p.clone())
    }

    /// Marks what a NetworkManager signal concerns
    fn note(&mut self, message: &zbus::Message) {
        let header = message.header();
        let (Some(path), Some(interface), Some(member)) = (header.path(), header.interface(), header.member()) else {
            return;
        };
        let path = OwnedObjectPath::from(path.to_owned());
        let p = path.as_str();
        match (interface.as_str(), member.as_str()) {
            (IFACE_PROPERTIES, "PropertiesChanged") => {
                if p == NM_PATH {
                    self.dirty.status = true;
                    self.dirty.devices_list = true;
                } else if p.starts_with("/org/freedesktop/NetworkManager/Devices/") {
                    self.dirty.devices.insert(path);
                } else if p.starts_with("/org/freedesktop/NetworkManager/AccessPoint/") {
                    self.dirty.access_points.insert(path);
                } else if p.starts_with("/org/freedesktop/NetworkManager/ActiveConnection/") {
                    // An activation progressed: the status and the devices it runs on
                    self.dirty.status = true;
                    self.dirty.devices.extend(self.devices.keys().cloned());
                } else if p.starts_with("/org/freedesktop/NetworkManager/IP4Config/")
                    || p.starts_with("/org/freedesktop/NetworkManager/IP6Config/")
                {
                    self.dirty.devices.extend(self.devices.keys().cloned());
                }
            }
            (IFACE_WIRELESS, "AccessPointAdded" | "AccessPointRemoved") => {
                self.dirty.devices.insert(path);
            }
            (IFACE_SETTINGS, "NewConnection" | "ConnectionRemoved") | (IFACE_CONNECTION, "Updated" | "Removed") => {
                self.dirty.connections = true;
            }
            (IFACE_NM, "CheckPermissions") => self.dirty.permissions = true,
            (IFACE_NM, "DeviceAdded" | "DeviceRemoved") => self.dirty.devices_list = true,
            (IFACE_DEVICE, "StateChanged") => {
                if let Ok((new, _old, reason)) = message.body().deserialize::<(u32, u32, u32)>() {
                    self.device_state_changed(&path, new, reason);
                }
                self.dirty.devices.insert(path);
            }
            _ => {}
        }
    }

    /// Failures and successes are events for the frontends (docs/gnome-wifi-features.md, #9)
    fn device_state_changed(&self, path: &OwnedObjectPath, new: u32, reason: u32) {
        let Some(entry) = self.devices.get(path) else { return };
        if new == nmdefs::DEVICE_STATE_FAILED && reason != nmdefs::REASON_NO_SECRETS {
            self.send(BackendEvent::Event(Event::ActivationFailed {
                device_id: entry.device.id.clone(),
                connection_uuid: entry.device.active_connection_uuid.clone(),
                name: entry.active_connection_name.clone(),
                reason: nmdefs::state_reason(reason),
            }));
        }
    }
}

// --- Reading the state ---

async fn read_status(conn: &Connection, permissions: Permissions) -> zbus::Result<Status> {
    let root = ObjectPath::try_from(NM_PATH)?;
    let props = get_all(conn, &root, IFACE_NM).await?;
    let mut primary = PrimaryConnection::default();
    let active = path_of(&props, "PrimaryConnection").or_else(|| path_of(&props, "ActivatingConnection"));
    if let Some(active) = active {
        if let Ok(ac) = get_all(conn, &active, IFACE_ACTIVE).await {
            primary.kind = match string_of(&ac, "Type").as_str() {
                "802-11-wireless" => ConnectionType::Wifi,
                "802-3-ethernet" => ConnectionType::Ethernet,
                "vpn" | "wireguard" => ConnectionType::Vpn,
                _ => ConnectionType::Other,
            };
            primary.name = string_of(&ac, "Id");
            primary.uuid = string_of(&ac, "Uuid");
            // NM_ACTIVE_CONNECTION_STATE_ACTIVATING
            primary.activating = u32_of(&ac, "State") == 1;
            if let Some(device) = paths_of(&ac, "Devices").first() {
                if let Ok(d) = get_all(conn, device, IFACE_DEVICE).await {
                    primary.device_id = string_of(&d, "Interface");
                }
            }
        }
    }
    Ok(Status {
        running: true,
        networking_enabled: bool_of(&props, "NetworkingEnabled"),
        wireless_enabled: bool_of(&props, "WirelessEnabled"),
        wireless_hardware_enabled: bool_of(&props, "WirelessHardwareEnabled"),
        connectivity: nmdefs::connectivity(u32_of(&props, "Connectivity")),
        connectivity_check_uri: string_of(&props, "ConnectivityCheckUri"),
        primary,
        permissions,
    })
}

async fn read_permissions(conn: &Connection) -> Permissions {
    let reply = conn.call_method(Some(NM), NM_PATH, Some(IFACE_NM), "GetPermissions", &()).await;
    let map: HashMap<String, String> = reply.ok().and_then(|r| r.body().deserialize().ok()).unwrap_or_default();
    let get = |name: &str| nmdefs::permission(map.get(&format!("org.freedesktop.NetworkManager.{name}")).map_or("no", |s| s));
    Permissions {
        enable_disable_wifi: get("enable-disable-wifi"),
        network_control: get("network-control"),
        modify_own: get("settings.modify.own"),
        modify_system: get("settings.modify.system"),
        wifi_share_open: get("wifi.share.open"),
        wifi_share_protected: get("wifi.share.protected"),
    }
}

async fn read_ip(conn: &Connection, path: Option<OwnedObjectPath>, interface: &str) -> IpInfo {
    let Some(path) = path else { return IpInfo::default() };
    let Ok(props) = get_all(conn, &path, interface).await else { return IpInfo::default() };
    let mut info = IpInfo { gateway: string_of(&props, "Gateway"), ..Default::default() };
    for data in owned::<Vec<HashMap<String, OwnedValue>>>(&props, "AddressData").unwrap_or_default() {
        let address = string_of(&data, "address");
        let prefix = u32_of(&data, "prefix") as u8;
        if !address.is_empty() {
            info.addresses.push(IpAddress { address, prefix });
        }
    }
    if interface == IFACE_IP4 {
        for data in owned::<Vec<HashMap<String, OwnedValue>>>(&props, "NameserverData").unwrap_or_default() {
            info.dns.push(string_of(&data, "address"));
        }
    } else {
        for bytes in owned::<Vec<Vec<u8>>>(&props, "Nameservers").unwrap_or_default() {
            if let Ok(octets) = <[u8; 16]>::try_from(bytes.as_slice()) {
                info.dns.push(Ipv6Addr::from(octets).to_string());
            }
        }
    }
    info
}

async fn read_access_point(conn: &Connection, path: &OwnedObjectPath) -> Option<AccessPoint> {
    let props = get_all(conn, path, IFACE_AP).await.ok()?;
    let last_seen = props.get("LastSeen").and_then(|v| i32::try_from(&**v).ok()).unwrap_or(-1);
    Some(AccessPoint {
        bssid: string_of(&props, "HwAddress"),
        ssid: bytes_of(&props, "Ssid"),
        security: nmdefs::ap_security(u32_of(&props, "Flags"), u32_of(&props, "WpaFlags"), u32_of(&props, "RsnFlags")),
        mode: nmdefs::wifi_mode(u32_of(&props, "Mode")),
        strength: props.get("Strength").and_then(|v| u8::try_from(&**v).ok()).unwrap_or(0),
        frequency: u32_of(&props, "Frequency"),
        max_bitrate: u32_of(&props, "MaxBitrate"),
        last_seen: if last_seen < 0 { 0 } else { boot_to_epoch_ms(last_seen as i64 * 1000) },
    })
}

/// A Wi-Fi device as NetworkManager has it now; None for other devices and unmanaged ones
async fn read_device(conn: &Connection, path: &OwnedObjectPath) -> Option<(WifiDevice, Vec<OwnedObjectPath>, String, i64)> {
    let d = get_all(conn, path, IFACE_DEVICE).await.ok()?;
    if u32_of(&d, "DeviceType") != nmdefs::DEVICE_TYPE_WIFI || !bool_of(&d, "Managed") {
        return None;
    }
    let w = get_all(conn, path, IFACE_WIRELESS).await.ok()?;
    let (state, reason) = owned::<(u32, u32)>(&d, "StateReason").unwrap_or((u32_of(&d, "State"), 0));
    let capabilities = u32_of(&w, "WirelessCapabilities");
    let mut device = WifiDevice {
        id: string_of(&d, "Interface"),
        hw_address: string_of(&w, "HwAddress"),
        perm_hw_address: string_of(&w, "PermHwAddress"),
        state: nmdefs::device_state(state),
        state_reason: nmdefs::state_reason(reason),
        bitrate: u32_of(&w, "Bitrate"),
        bands: nmdefs::bands(capabilities),
        can_hotspot: nmdefs::can_hotspot(capabilities),
        ..Default::default()
    };
    let mut active_name = String::new();
    if let Some(active) = path_of(&d, "ActiveConnection") {
        if let Ok(ac) = get_all(conn, &active, IFACE_ACTIVE).await {
            device.active_connection_uuid = string_of(&ac, "Uuid");
            active_name = string_of(&ac, "Id");
        }
        device.ip4 = read_ip(conn, path_of(&d, "Ip4Config"), IFACE_IP4).await;
        device.ip6 = read_ip(conn, path_of(&d, "Ip6Config"), IFACE_IP6).await;
    }
    if let Some(ap) = path_of(&w, "ActiveAccessPoint") {
        if let Ok(props) = get_all(conn, &ap, IFACE_AP).await {
            device.active_ssid = bytes_of(&props, "Ssid");
        }
    }
    Some((device, paths_of(&w, "AccessPoints"), active_name, i64_of(&w, "LastScan")))
}

/// A saved Wi-Fi profile; None for other profiles
fn saved_connection(dict: &SettingsDict) -> Option<SavedConnection> {
    let c = setting(dict, "connection")?;
    if string_of(c, "type") != "802-11-wireless" {
        return None;
    }
    let empty = Props::new();
    let w = setting(dict, "802-11-wireless").unwrap_or(&empty);
    let s = setting(dict, "802-11-wireless-security").unwrap_or(&empty);
    let ip4 = setting(dict, "ipv4").unwrap_or(&empty);
    let permissions = owned::<Vec<String>>(c, "permissions").unwrap_or_default();
    let timestamp = c.get("timestamp").and_then(|v| u64::try_from(&**v).ok()).unwrap_or(0);
    let metered = c.get("metered").and_then(|v| i32::try_from(&**v).ok()).unwrap_or(0);
    Some(SavedConnection {
        uuid: string_of(c, "uuid"),
        name: string_of(c, "id"),
        ssid: bytes_of(w, "ssid"),
        security: nmdefs::profile_security(&string_of(s, "key-mgmt"), &string_of(s, "auth-alg"), false),
        hidden: bool_of(w, "hidden"),
        hotspot: string_of(w, "mode") == "ap" || string_of(ip4, "method") == "shared",
        // NetworkManager leaves out what has its default value: autoconnect is true unless given
        autoconnect: c.get("autoconnect").and_then(|v| bool::try_from(&**v).ok()).unwrap_or(true),
        metered: match metered {
            1 | 3 => Metered::Yes,
            2 | 4 => Metered::No,
            _ => Metered::Unknown,
        },
        available_to_all: permissions.is_empty(),
        last_used: timestamp as i64 * 1000,
        active_device_id: String::new(),
        interface_name: string_of(c, "interface-name"),
    })
}

// --- Refreshing: read what is dirty, send what changed ---

async fn refresh(state: &StateRef) {
    let (conn, dirty) = {
        let mut s = state.borrow_mut();
        (s.conn.clone(), std::mem::take(&mut s.dirty))
    };

    if dirty.connections {
        refresh_connections(state, &conn).await;
    }
    if dirty.devices_list {
        refresh_device_list(state, &conn).await;
    }
    let mut devices: HashSet<OwnedObjectPath> = dirty.devices;
    // A changed access point is published with the list of its device
    for ap in &dirty.access_points {
        let owner = state.borrow().ap_owner.get(ap).cloned();
        if let (Some(owner), Some(read)) = (owner, read_access_point(&conn, ap).await) {
            if let Some(entry) = state.borrow_mut().devices.get_mut(&owner) {
                entry.access_points.insert(ap.clone(), read);
            }
            devices.insert(owner);
        }
    }
    for path in devices {
        refresh_device(state, &conn, &path).await;
    }
    sync_active_connections(state);
    if dirty.status || dirty.permissions {
        let permissions = if dirty.permissions || !state.borrow().status.running {
            read_permissions(&conn).await
        } else {
            state.borrow().status.permissions.clone()
        };
        if let Ok(status) = read_status(&conn, permissions).await {
            let mut s = state.borrow_mut();
            if s.status != status {
                s.status = status.clone();
                s.send(BackendEvent::Status(status));
            }
        }
    }
}

async fn refresh_connections(state: &StateRef, conn: &Connection) {
    let Ok(reply) = conn.call_method(Some(NM), SETTINGS_PATH, Some(IFACE_SETTINGS), "ListConnections", &()).await else {
        return;
    };
    let paths: Vec<OwnedObjectPath> = reply.body().deserialize().unwrap_or_default();
    let mut read = HashMap::new();
    for path in paths {
        let Ok(reply) = conn.call_method(Some(NM), &path, Some(IFACE_CONNECTION), "GetSettings", &()).await else {
            continue;
        };
        let Ok(dict) = reply.body().deserialize::<SettingsDict>() else { continue };
        if let Some(connection) = saved_connection(&dict) {
            read.insert(path, connection);
        }
    }
    let mut s = state.borrow_mut();
    for connection in read.values_mut() {
        connection.active_device_id = s.active_device_of(&connection.uuid);
    }
    let gone: Vec<String> =
        s.connections.iter().filter(|(p, _)| !read.contains_key(*p)).map(|(_, c)| c.uuid.clone()).collect();
    for uuid in gone {
        s.send(BackendEvent::ConnectionRemoved(uuid));
    }
    for (path, connection) in &read {
        if s.connections.get(path) != Some(connection) {
            s.send(BackendEvent::Connection(connection.clone()));
        }
    }
    s.connections = read;
}

/// Where each profile is active follows the devices: sends the profiles whose device changed
fn sync_active_connections(state: &StateRef) {
    let mut s = state.borrow_mut();
    let changed: Vec<(OwnedObjectPath, String)> = s
        .connections
        .iter()
        .map(|(path, c)| (path.clone(), s.active_device_of(&c.uuid)))
        .filter(|(path, device)| s.connections.get(path).is_some_and(|c| &c.active_device_id != device))
        .collect();
    for (path, device) in changed {
        if let Some(connection) = s.connections.get_mut(&path) {
            connection.active_device_id = device;
            let connection = connection.clone();
            s.send(BackendEvent::Connection(connection));
        }
    }
}

async fn refresh_device_list(state: &StateRef, conn: &Connection) {
    let Ok(root) = ObjectPath::try_from(NM_PATH) else { return };
    let Ok(props) = get_all(conn, &root, IFACE_NM).await else { return };
    let paths = paths_of(&props, "Devices");
    let known: Vec<OwnedObjectPath> = state.borrow().devices.keys().cloned().collect();
    for path in &known {
        if !paths.contains(path) {
            remove_device(state, path);
        }
    }
    for path in paths {
        refresh_device(state, conn, &path).await;
    }
}

fn remove_device(state: &StateRef, path: &OwnedObjectPath) {
    let mut s = state.borrow_mut();
    if let Some(entry) = s.devices.remove(path) {
        s.ap_owner.retain(|_, owner| owner != path);
        s.send(BackendEvent::DeviceRemoved(entry.device.id));
    }
}

async fn refresh_device(state: &StateRef, conn: &Connection, path: &OwnedObjectPath) {
    let Some((mut device, ap_paths, active_name, last_scan)) = read_device(conn, path).await else {
        remove_device(state, path);
        return;
    };
    // Access points: read the new ones, keep the known ones (their changes arrive as signals)
    let known: HashMap<OwnedObjectPath, AccessPoint> =
        state.borrow().devices.get(path).map(|e| e.access_points.clone()).unwrap_or_default();
    let mut access_points = HashMap::new();
    for ap in &ap_paths {
        match known.get(ap) {
            Some(read) => {
                access_points.insert(ap.clone(), read.clone());
            }
            None => {
                if let Some(read) = read_access_point(conn, ap).await {
                    access_points.insert(ap.clone(), read);
                }
            }
        }
    }

    let mut s = state.borrow_mut();
    let previous = s.devices.remove(path);
    let mut scan_requested = previous.as_ref().and_then(|e| e.scan_requested);
    if let Some((requested_at_scan, since)) = scan_requested {
        if last_scan != requested_at_scan || since.elapsed() > SCAN_TIMEOUT {
            scan_requested = None;
        }
    }
    device.scanning = scan_requested.is_some();
    device.last_scan = boot_to_epoch_ms(last_scan);
    device.hotspot = s.connections.values().any(|c| c.hotspot && c.uuid == device.active_connection_uuid);
    if s.devices.values().filter(|e| e.device.id != device.id).count() > 0 {
        // Several adapters: tell them apart by interface name
        device.name = device.id.clone();
    }

    let aps_changed = previous.as_ref().is_none_or(|e| e.access_points != access_points);
    let device_changed = previous.as_ref().is_none_or(|e| e.device != device);
    s.ap_owner.retain(|_, owner| owner != path);
    for ap in access_points.keys() {
        s.ap_owner.insert(ap.clone(), path.clone());
    }
    if device_changed {
        s.send(BackendEvent::Device(device.clone()));
    }
    if aps_changed {
        let mut list: Vec<AccessPoint> = access_points.values().cloned().collect();
        list.sort_by(|a, b| a.bssid.cmp(&b.bssid));
        s.send(BackendEvent::AccessPoints { device_id: device.id.clone(), access_points: list });
    }
    s.devices.insert(
        path.clone(),
        DeviceEntry { device, access_points, active_connection_name: active_name, scan_requested },
    );
}

// --- Commands ---

fn not_found(what: &str) -> OpError {
    OpError::new(ErrorCode::NotFound, format!("no {what}"))
}

fn no_object() -> OwnedObjectPath {
    OwnedObjectPath::try_from("/").expect("valid path")
}

async fn execute(state: StateRef, command: Command) {
    let conn = state.borrow().conn.clone();
    match command {
        Command::SetWirelessEnabled { enabled, reply } => {
            let result = call::<_, ()>(&conn, NM_PATH, IFACE_PROPERTIES, "Set", &(IFACE_NM, "WirelessEnabled", Value::from(enabled)))
                .await;
            let _ = reply.send(result);
        }
        Command::RequestScan { device_id, reply } => {
            let devices: Vec<OwnedObjectPath> = {
                let s = state.borrow();
                s.devices.iter().filter(|(_, e)| device_id.is_empty() || e.device.id == device_id).map(|(p, _)| p.clone()).collect()
            };
            if devices.is_empty() {
                let _ = reply.send(Err(not_found("Wi-Fi device")));
                return;
            }
            let mut result = Ok(());
            for path in devices {
                let options: HashMap<String, Value> = HashMap::new();
                match call::<_, ()>(&conn, path.as_str(), IFACE_WIRELESS, "RequestScan", &(options,)).await {
                    Ok(()) => {
                        let mut s = state.borrow_mut();
                        if let Some(entry) = s.devices.get_mut(&path) {
                            let at = entry.device.last_scan;
                            // The scan is over when LastScan (boot ms) changes; remember the current one
                            let boot = if at == 0 { 0 } else { at - now_ms() + boottime_ms() };
                            entry.scan_requested = Some((boot, Instant::now()));
                            entry.device.scanning = true;
                            let device = entry.device.clone();
                            s.send(BackendEvent::Device(device));
                        }
                    }
                    // NetworkManager refuses scans too close together: nothing to tell the user
                    Err(error) => result = Err(error),
                }
            }
            let _ = reply.send(result);
        }
        Command::ConnectNetwork { device_id, connection_uuid, bssid, reply, .. } => {
            let (device, connection, ap, modify_system) = {
                let s = state.borrow();
                let device = s.device_path(&device_id);
                let ap = device.as_ref().and_then(|d| s.access_point_path(d, &bssid));
                let connection = connection_uuid.as_deref().and_then(|uuid| s.connection_path(uuid));
                (device, connection, ap, s.status.permissions.modify_system == Permission::Yes)
            };
            let Some(device) = device else {
                let _ = reply.send(Err(not_found("Wi-Fi device")));
                return;
            };
            let ap = ap.unwrap_or_else(no_object);
            let result = match connection {
                Some(connection) => call::<_, OwnedObjectPath>(&conn, NM_PATH, IFACE_NM, "ActivateConnection", &(connection, device, ap))
                    .await
                    .map(|_| ()),
                None => {
                    // An almost empty profile: NetworkManager fills it from the access point and asks
                    // the secret agent for the password. Without the permission to change system
                    // profiles it is this user's alone, as GNOME does it.
                    let mut partial: HashMap<&str, HashMap<&str, Value>> = HashMap::new();
                    if !modify_system {
                        let user = std::env::var("USER").unwrap_or_default();
                        let mut c = HashMap::new();
                        c.insert("permissions", Value::from(vec![format!("user:{user}:")]));
                        partial.insert("connection", c);
                    }
                    call::<_, (OwnedObjectPath, OwnedObjectPath)>(&conn, NM_PATH, IFACE_NM, "AddAndActivateConnection", &(partial, device, ap))
                        .await
                        .map(|_| ())
                }
            };
            let _ = reply.send(result);
        }
        Command::Activate { uuid, device_id, reply } => {
            let (connection, device) = {
                let s = state.borrow();
                (s.connection_path(&uuid), if device_id.is_empty() { Some(no_object()) } else { s.device_path(&device_id) })
            };
            let result = match (connection, device) {
                (Some(connection), Some(device)) => {
                    call::<_, OwnedObjectPath>(&conn, NM_PATH, IFACE_NM, "ActivateConnection", &(connection, device, no_object()))
                        .await
                        .map(|_| ())
                }
                (None, _) => Err(not_found("connection")),
                (_, None) => Err(not_found("Wi-Fi device")),
            };
            let _ = reply.send(result);
        }
        Command::Disconnect { device_id, reply } => {
            let device = state.borrow().device_path(&device_id);
            let result = match device {
                Some(device) => call::<_, ()>(&conn, device.as_str(), IFACE_DEVICE, "Disconnect", &()).await,
                None => Err(not_found("Wi-Fi device")),
            };
            let _ = reply.send(result);
        }
        Command::Forget { uuid, reply } => {
            let connection = state.borrow().connection_path(&uuid);
            let result = match connection {
                Some(connection) => call::<_, ()>(&conn, connection.as_str(), IFACE_CONNECTION, "Delete", &()).await,
                None => Err(not_found("connection")),
            };
            let _ = reply.send(result);
        }
        Command::CheckConnectivity { reply } => {
            let result = call::<_, u32>(&conn, NM_PATH, IFACE_NM, "CheckConnectivity", &()).await.map(|_| ());
            let _ = reply.send(result);
        }
        Command::ConnectWithSettings { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
        Command::Settings { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
        Command::UpdateSettings { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
        Command::Secrets { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
        Command::StartHotspot { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
        Command::StopHotspot { reply, .. } => {
            let _ = reply.send(Err(not_yet()));
        }
    }
}

/// Makes this process the secret agent of the user's session (again after NetworkManager restarted)
async fn register_agent(conn: &Connection) {
    let result = conn
        .call_method(
            Some(NM),
            "/org/freedesktop/NetworkManager/AgentManager",
            Some("org.freedesktop.NetworkManager.AgentManager"),
            "Register",
            &(agent::IDENTIFIER,),
        )
        .await;
    if let Err(error) = result {
        eprintln!("maia-network-service: registering the secret agent: {error}");
    }
}

fn not_yet() -> OpError {
    OpError::new(ErrorCode::NotSupported, "not implemented in the NetworkManager backend yet")
}

/// Runs the backend until NetworkManager's bus connection fails
pub async fn run(
    events: mpsc::UnboundedSender<BackendEvent>,
    mut commands: mpsc::UnboundedReceiver<Command>,
    prompter: Prompter,
) -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::system().await?;
    conn.object_server().at(agent::PATH, Agent::new(prompter)).await?;
    register_agent(&conn).await;
    let rule = MatchRule::builder().msg_type(MessageType::Signal).sender(NM)?.build();
    let mut signals = MessageStream::for_match_rule(rule, &conn, Some(1024)).await?;
    let owner_rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .sender("org.freedesktop.DBus")?
        .interface("org.freedesktop.DBus")?
        .member("NameOwnerChanged")?
        .arg(0, NM)?
        .build();
    let mut owner = MessageStream::for_match_rule(owner_rule, &conn, None).await?;

    let state = Rc::new(RefCell::new(State {
        conn,
        events,
        status: Status::default(),
        devices: HashMap::new(),
        ap_owner: HashMap::new(),
        connections: HashMap::new(),
        dirty: Dirty::everything(),
    }));
    refresh(&state).await;
    if !state.borrow().status.running {
        // NetworkManager is not there (yet): say so, it is picked up when it starts
        let s = state.borrow();
        s.send(BackendEvent::Status(Status::default()));
    }

    let mut settle: Option<tokio::time::Instant> = None;
    loop {
        tokio::select! {
            Some(message) = signals.next() => {
                if let Ok(message) = message {
                    state.borrow_mut().note(&message);
                    if state.borrow().dirty.any() && settle.is_none() {
                        settle = Some(tokio::time::Instant::now() + SETTLE);
                    }
                }
            }
            Some(message) = owner.next() => {
                if let Ok(message) = message {
                    let (_, _, new_owner) = message.body().deserialize::<(String, String, String)>().unwrap_or_default();
                    if new_owner.is_empty() {
                        // NetworkManager stopped: everything is gone
                        let mut s = state.borrow_mut();
                        let paths: Vec<OwnedObjectPath> = s.devices.keys().cloned().collect();
                        drop(s);
                        for path in paths {
                            remove_device(&state, &path);
                        }
                        s = state.borrow_mut();
                        for connection in s.connections.drain().map(|(_, c)| c.uuid).collect::<Vec<_>>() {
                            s.send(BackendEvent::ConnectionRemoved(connection));
                        }
                        s.status = Status::default();
                        s.send(BackendEvent::Status(Status::default()));
                    } else {
                        // No borrow of the state across the await
                        let conn = state.borrow().conn.clone();
                        register_agent(&conn).await;
                        state.borrow_mut().dirty = Dirty::everything();
                        settle = Some(tokio::time::Instant::now() + SETTLE);
                    }
                }
            }
            Some(command) = commands.recv() => {
                tokio::task::spawn_local(execute(state.clone(), command));
            }
            _ = async { tokio::time::sleep_until(settle.unwrap()).await }, if settle.is_some() => {
                settle = None;
                refresh(&state).await;
            }
            else => break,
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Security;

    fn value<'a, T: Into<Value<'a>>>(v: T) -> OwnedValue {
        OwnedValue::try_from(v.into()).unwrap()
    }

    #[test]
    fn a_saved_wifi_profile_is_read_with_its_defaults() {
        let mut dict = SettingsDict::new();
        let mut c = Props::new();
        c.insert("type".into(), value("802-11-wireless"));
        c.insert("id".into(), value("Home"));
        c.insert("uuid".into(), value("u1"));
        c.insert("timestamp".into(), value(1_700_000_000u64));
        c.insert("permissions".into(), value(vec!["user:kubuntu:".to_string()]));
        dict.insert("connection".into(), c);
        let mut w = Props::new();
        w.insert("ssid".into(), value(b"Home".to_vec()));
        dict.insert("802-11-wireless".into(), w);
        let mut s = Props::new();
        s.insert("key-mgmt".into(), value("wpa-psk"));
        dict.insert("802-11-wireless-security".into(), s);

        let connection = saved_connection(&dict).unwrap();
        assert_eq!(connection.name, "Home");
        assert_eq!(connection.ssid, b"Home");
        assert_eq!(connection.security, Security::WpaPersonal);
        assert!(connection.autoconnect, "left out means true");
        assert!(!connection.available_to_all, "limited to one user");
        assert_eq!(connection.last_used, 1_700_000_000_000);
        assert!(!connection.hotspot);
    }

    #[test]
    fn other_profiles_are_left_out() {
        let mut dict = SettingsDict::new();
        let mut c = Props::new();
        c.insert("type".into(), value("802-3-ethernet"));
        dict.insert("connection".into(), c);
        assert!(saved_connection(&dict).is_none());
    }
}
