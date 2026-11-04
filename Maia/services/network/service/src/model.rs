//! The state of the network as the service keeps it: plain values, no Cap'n Proto, no D-Bus.
//!
//! Backends fill these types from NetworkManager (or from the fake backend); rpc.rs writes them into
//! the contract. The one piece of logic here is how access points become networks
//! (`networks_of_device`): the access points a device sees with the same SSID, mode and security
//! are one network, as in GNOME (docs/gnome-wifi-features.md, section 2).

use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Connectivity {
    #[default]
    Unknown,
    None,
    Portal,
    Limited,
    Full,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Permission {
    #[default]
    No,
    Auth,
    Yes,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Permissions {
    pub enable_disable_wifi: Permission,
    pub network_control: Permission,
    pub modify_own: Permission,
    pub modify_system: Permission,
    pub wifi_share_open: Permission,
    pub wifi_share_protected: Permission,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ConnectionType {
    #[default]
    None,
    Wifi,
    Ethernet,
    Vpn,
    Other,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct PrimaryConnection {
    pub kind: ConnectionType,
    pub name: String,
    pub uuid: String,
    pub device_id: String,
    pub activating: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Status {
    pub running: bool,
    pub networking_enabled: bool,
    pub wireless_enabled: bool,
    pub wireless_hardware_enabled: bool,
    pub connectivity: Connectivity,
    pub connectivity_check_uri: String,
    pub primary: PrimaryConnection,
    pub permissions: Permissions,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum DeviceState {
    #[default]
    Unknown,
    Unmanaged,
    Unavailable,
    Disconnected,
    Connecting,
    NeedAuth,
    Connected,
    Disconnecting,
    Failed,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum StateReason {
    #[default]
    None,
    Other,
    NoSecrets,
    WrongSecrets,
    SupplicantFailed,
    SupplicantTimeout,
    ConfigFailed,
    IpConfigFailed,
    IpConfigExpired,
    ConnectionRemoved,
    SsidNotFound,
    FirmwareMissing,
    UserRequested,
    CarrierLost,
}

/// Bits of `bands` (contract band* constants)
pub const BAND_2_4_GHZ: u8 = 0x1;
pub const BAND_5_GHZ: u8 = 0x2;
pub const BAND_6_GHZ: u8 = 0x4;

/// The band of a frequency in MHz (0 when unknown)
pub fn band_of(frequency: u32) -> u8 {
    match frequency {
        2400..=2500 => BAND_2_4_GHZ,
        4900..=5900 => BAND_5_GHZ,
        5925..=7125 => BAND_6_GHZ,
        _ => 0,
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct IpAddress {
    pub address: String,
    pub prefix: u8,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct IpInfo {
    pub addresses: Vec<IpAddress>,
    pub gateway: String,
    pub dns: Vec<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WifiDevice {
    /// Interface name, e.g. "wlp2s0"
    pub id: String,
    /// Tells several adapters apart; empty when there is only one
    pub name: String,
    pub hw_address: String,
    pub perm_hw_address: String,
    pub state: DeviceState,
    pub state_reason: StateReason,
    /// Filled in by the store from the networks (`networks_of_device`), not by backends
    pub active_network_id: String,
    pub active_connection_uuid: String,
    /// The SSID of the active access point, to find the active network
    pub active_ssid: Vec<u8>,
    pub hotspot: bool,
    /// kbit/s
    pub bitrate: u32,
    pub bands: u8,
    pub can_hotspot: bool,
    pub scanning: bool,
    /// ms since 1970, 0 = never
    pub last_scan: i64,
    pub ip4: IpInfo,
    pub ip6: IpInfo,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Security {
    #[default]
    None,
    EnhancedOpen,
    Wep,
    Leap,
    WpaPersonal,
    Wpa3Personal,
    WpaEnterprise,
    Wpa3Enterprise,
}

impl Security {
    /// The name in network ids
    pub fn id_name(self) -> &'static str {
        match self {
            Security::None => "none",
            Security::EnhancedOpen => "owe",
            Security::Wep => "wep",
            Security::Leap => "leap",
            Security::WpaPersonal => "wpa-psk",
            Security::Wpa3Personal => "sae",
            Security::WpaEnterprise => "wpa-eap",
            Security::Wpa3Enterprise => "wpa3-eap",
        }
    }

    /// Whether a saved profile of security `self` can be used with an access point of `other`.
    /// Personal profiles work for WPA2 and WPA3 transition networks alike, so they count as one.
    pub fn fits(self, other: Security) -> bool {
        self.class() == other.class()
    }

    fn class(self) -> u8 {
        match self {
            Security::None | Security::EnhancedOpen => 0,
            Security::Wep => 1,
            Security::Leap => 2,
            Security::WpaPersonal | Security::Wpa3Personal => 3,
            Security::WpaEnterprise | Security::Wpa3Enterprise => 4,
        }
    }

    pub fn is_enterprise(self) -> bool {
        matches!(self, Security::WpaEnterprise | Security::Wpa3Enterprise)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum WifiMode {
    #[default]
    Infrastructure,
    Adhoc,
    AccessPoint,
}

/// One access point as a backend reports it
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AccessPoint {
    pub bssid: String,
    pub ssid: Vec<u8>,
    pub security: Security,
    pub mode: WifiMode,
    /// 0..100
    pub strength: u8,
    /// MHz
    pub frequency: u32,
    /// kbit/s
    pub max_bitrate: u32,
    /// ms since 1970
    pub last_seen: i64,
}

/// Access points of one device merged into a network
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WifiNetwork {
    pub id: String,
    pub device_id: String,
    pub ssid: Vec<u8>,
    pub name: String,
    pub security: Security,
    pub mode: WifiMode,
    pub strength: u8,
    pub frequency: u32,
    pub bands: u8,
    pub connection_uuids: Vec<String>,
    pub active: bool,
    /// Strongest first
    pub access_points: Vec<AccessPoint>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Metered {
    #[default]
    Unknown,
    Yes,
    No,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SavedConnection {
    pub uuid: String,
    pub name: String,
    pub ssid: Vec<u8>,
    pub security: Security,
    pub hidden: bool,
    pub hotspot: bool,
    pub autoconnect: bool,
    pub metered: Metered,
    pub available_to_all: bool,
    /// ms since 1970, 0 = never
    pub last_used: i64,
    pub active_device_id: String,
    /// Restricted to one interface ("" = any)
    pub interface_name: String,
}

impl SavedConnection {
    pub fn ssid_text(&self) -> String {
        ssid_to_text(&self.ssid)
    }

    /// Sharing by QR code works for open and Personal networks
    pub fn qr_supported(&self) -> bool {
        matches!(
            self.security,
            Security::None | Security::EnhancedOpen | Security::Wep | Security::WpaPersonal | Security::Wpa3Personal
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Event {
    ActivationFailed { device_id: String, connection_uuid: String, name: String, reason: StateReason },
    Connected(String),
}

pub fn ssid_to_text(ssid: &[u8]) -> String {
    String::from_utf8_lossy(ssid).into_owned()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn network_id(device_id: &str, ssid: &[u8], security: Security) -> String {
    format!("{device_id}/{}/{}", hex(ssid), security.id_name())
}

/// The networks a device sees: its access points merged by SSID, mode and security, each with the
/// saved profiles that fit it. Access points without an SSID (hidden networks) are left out. The
/// result is ordered by id; frontends order for display.
pub fn networks_of_device(
    device: &WifiDevice,
    access_points: &[AccessPoint],
    connections: &[SavedConnection],
) -> Vec<WifiNetwork> {
    let mut groups: BTreeMap<(Vec<u8>, WifiMode, Security), Vec<AccessPoint>> = BTreeMap::new();
    for ap in access_points.iter().filter(|ap| !ap.ssid.is_empty()) {
        groups.entry((ap.ssid.clone(), ap.mode, ap.security)).or_default().push(ap.clone());
    }

    let mut networks: Vec<WifiNetwork> = groups
        .into_iter()
        .map(|((ssid, mode, security), mut aps)| {
            aps.sort_by(|a, b| b.strength.cmp(&a.strength).then_with(|| a.bssid.cmp(&b.bssid)));
            let best = &aps[0];
            let connection_uuids = connections
                .iter()
                .filter(|c| {
                    !c.hotspot
                        && c.ssid == ssid
                        && c.security.fits(security)
                        && (c.interface_name.is_empty() || c.interface_name == device.id)
                })
                .map(|c| c.uuid.clone())
                .collect::<Vec<_>>();
            let active = !device.active_connection_uuid.is_empty()
                && !device.hotspot
                && (connection_uuids.contains(&device.active_connection_uuid) || device.active_ssid == ssid);
            WifiNetwork {
                id: network_id(&device.id, &ssid, security),
                device_id: device.id.clone(),
                name: ssid_to_text(&ssid),
                security,
                mode,
                strength: best.strength,
                frequency: best.frequency,
                bands: aps.iter().fold(0, |bands, ap| bands | band_of(ap.frequency)),
                connection_uuids,
                active,
                access_points: aps.clone(),
                ssid,
            }
        })
        .collect();
    networks.sort_by(|a, b| a.id.cmp(&b.id));
    networks
}

/// What changed in a keyed collection
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Change<T> {
    Changed(T),
    Removed(String),
}

/// Objects by id, telling what really changed
#[derive(Clone, Debug)]
pub struct KeyedStore<T> {
    items: BTreeMap<String, T>,
}

impl<T> Default for KeyedStore<T> {
    fn default() -> Self {
        Self { items: BTreeMap::new() }
    }
}

impl<T: Clone + PartialEq> KeyedStore<T> {
    /// Stores `value`; returns it when it is new or different
    pub fn upsert(&mut self, id: &str, value: T) -> Option<Change<T>> {
        if self.items.get(id) == Some(&value) {
            return None;
        }
        self.items.insert(id.to_string(), value.clone());
        Some(Change::Changed(value))
    }

    pub fn remove(&mut self, id: &str) -> Option<Change<T>> {
        self.items.remove(id).map(|_| Change::Removed(id.to_string()))
    }

    /// Makes the store hold exactly `values`; returns every change
    pub fn replace_all(&mut self, values: Vec<(String, T)>) -> Vec<Change<T>> {
        let mut changes = Vec::new();
        let ids: Vec<String> = values.iter().map(|(id, _)| id.clone()).collect();
        let gone: Vec<String> = self.items.keys().filter(|id| !ids.contains(id)).cloned().collect();
        for id in gone {
            changes.extend(self.remove(&id));
        }
        for (id, value) in values {
            changes.extend(self.upsert(&id, value));
        }
        changes
    }

    pub fn get(&self, id: &str) -> Option<&T> {
        self.items.get(id)
    }

    pub fn values(&self) -> impl Iterator<Item = &T> {
        self.items.values()
    }

    pub fn ids(&self) -> impl Iterator<Item = &String> {
        self.items.keys()
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ap(bssid: &str, ssid: &str, security: Security, strength: u8, frequency: u32) -> AccessPoint {
        AccessPoint {
            bssid: bssid.into(),
            ssid: ssid.as_bytes().to_vec(),
            security,
            strength,
            frequency,
            ..Default::default()
        }
    }

    fn device() -> WifiDevice {
        WifiDevice { id: "wlan0".into(), ..Default::default() }
    }

    #[test]
    fn access_points_with_the_same_ssid_and_security_are_one_network() {
        let aps = [
            ap("aa", "Home", Security::WpaPersonal, 40, 2412),
            ap("bb", "Home", Security::WpaPersonal, 80, 5180),
            ap("cc", "Home", Security::None, 30, 2437),
            ap("dd", "", Security::WpaPersonal, 90, 2462),
        ];
        let networks = networks_of_device(&device(), &aps, &[]);
        assert_eq!(networks.len(), 2, "hidden access point left out, open Home apart");
        let home = networks.iter().find(|n| n.security == Security::WpaPersonal).unwrap();
        assert_eq!(home.strength, 80);
        assert_eq!(home.frequency, 5180);
        assert_eq!(home.bands, BAND_2_4_GHZ | BAND_5_GHZ);
        assert_eq!(home.access_points[0].bssid, "bb", "strongest first");
        assert_eq!(home.id, "wlan0/486f6d65/wpa-psk");
    }

    #[test]
    fn saved_profiles_fit_by_ssid_security_class_and_interface() {
        let aps = [ap("aa", "Home", Security::Wpa3Personal, 50, 2412)];
        let connections = [
            SavedConnection { uuid: "u1".into(), ssid: b"Home".to_vec(), security: Security::WpaPersonal, ..Default::default() },
            SavedConnection { uuid: "u2".into(), ssid: b"Home".to_vec(), security: Security::None, ..Default::default() },
            SavedConnection {
                uuid: "u3".into(),
                ssid: b"Home".to_vec(),
                security: Security::WpaPersonal,
                interface_name: "wlan1".into(),
                ..Default::default()
            },
            SavedConnection {
                uuid: "u4".into(),
                ssid: b"Home".to_vec(),
                security: Security::WpaPersonal,
                hotspot: true,
                ..Default::default()
            },
        ];
        let networks = networks_of_device(&device(), &aps, &connections);
        assert_eq!(networks[0].connection_uuids, vec!["u1".to_string()]);
    }

    #[test]
    fn the_active_network_follows_the_active_profile() {
        let aps = [ap("aa", "Home", Security::WpaPersonal, 50, 2412), ap("bb", "Cafe", Security::None, 50, 2412)];
        let connections =
            [SavedConnection { uuid: "u1".into(), ssid: b"Home".to_vec(), security: Security::WpaPersonal, ..Default::default() }];
        let device = WifiDevice { active_connection_uuid: "u1".into(), ..device() };
        let networks = networks_of_device(&device, &aps, &connections);
        let active: Vec<_> = networks.iter().filter(|n| n.active).map(|n| n.name.as_str()).collect();
        assert_eq!(active, vec!["Home"]);
    }

    #[test]
    fn store_reports_only_real_changes() {
        let mut store = KeyedStore::default();
        assert!(store.upsert("a", 1).is_some());
        assert!(store.upsert("a", 1).is_none());
        assert_eq!(store.upsert("a", 2), Some(Change::Changed(2)));
        let changes = store.replace_all(vec![("b".into(), 3)]);
        assert_eq!(changes, vec![Change::Removed("a".into()), Change::Changed(3)]);
    }
}
