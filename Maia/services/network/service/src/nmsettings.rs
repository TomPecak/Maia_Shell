//! NetworkManager profiles (a{sa{sv}}, see `man nm-settings-dbus`) and the contract's
//! ConnectionSettings and secrets, both ways.
//!
//! Reading takes what the details editor shows (docs/gnome-wifi-features.md, section 10). Writing
//! changes those keys in the profile as it is and keeps everything else, so settings Maia does not
//! know survive an edit. New profiles (hidden and Enterprise networks, the hotspot) are built here
//! too. Pure functions over dictionaries, tested without NetworkManager.

use std::collections::HashMap;
use std::net::{Ipv4Addr, Ipv6Addr};

use zbus::zvariant::{OwnedValue, Value};

use crate::model::{IpAddress, Metered, Security};
use crate::settings::{
    ClonedMac, ConnectionSettings, Eap8021xSettings, EapMethod, InnerAuth, IpMethod, IpSettings, Route, Secret, SecretKey,
    SecuritySettings, WifiSettings, find_secret,
};

pub type Props = HashMap<String, OwnedValue>;
pub type SettingsDict = HashMap<String, HashMap<String, OwnedValue>>;

// --- Reading values ---

fn get<'a>(dict: &'a SettingsDict, setting: &str, key: &str) -> Option<&'a OwnedValue> {
    dict.get(setting).and_then(|p| p.get(key))
}

fn text(dict: &SettingsDict, setting: &str, key: &str) -> String {
    get(dict, setting, key).and_then(|v| <&str>::try_from(&**v).ok()).map(str::to_string).unwrap_or_default()
}

fn flag(dict: &SettingsDict, setting: &str, key: &str, default: bool) -> bool {
    get(dict, setting, key).and_then(|v| bool::try_from(&**v).ok()).unwrap_or(default)
}

fn number<T: for<'v> TryFrom<&'v Value<'v>>>(dict: &SettingsDict, setting: &str, key: &str) -> Option<T> {
    get(dict, setting, key).and_then(|v| T::try_from(&**v).ok())
}

fn owned<T: TryFrom<OwnedValue>>(value: Option<&OwnedValue>) -> Option<T> {
    value.and_then(|v| v.try_clone().ok()).and_then(|v| T::try_from(v).ok())
}

fn bytes(dict: &SettingsDict, setting: &str, key: &str) -> Vec<u8> {
    owned::<Vec<u8>>(get(dict, setting, key)).unwrap_or_default()
}

fn strings(dict: &SettingsDict, setting: &str, key: &str) -> Vec<String> {
    owned::<Vec<String>>(get(dict, setting, key)).unwrap_or_default()
}

fn mac_to_text(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02X}")).collect::<Vec<_>>().join(":")
}

fn mac_from_text(text: &str) -> Option<Vec<u8>> {
    let bytes: Result<Vec<u8>, _> = text.split(':').map(|part| u8::from_str_radix(part, 16)).collect();
    bytes.ok().filter(|b| b.len() == 6)
}

/// "file:///path\0" in a byte array (certificates, keys) -> "/path"
fn path_from_blob(blob: &[u8]) -> String {
    let text = String::from_utf8_lossy(blob.strip_suffix(&[0]).unwrap_or(blob)).into_owned();
    text.strip_prefix("file://").map(str::to_string).unwrap_or_default()
}

fn blob_from_path(path: &str) -> Vec<u8> {
    let mut blob = format!("file://{path}").into_bytes();
    blob.push(0);
    blob
}

fn read_addresses(value: Option<&OwnedValue>) -> Vec<IpAddress> {
    owned::<Vec<HashMap<String, OwnedValue>>>(value)
        .unwrap_or_default()
        .iter()
        .filter_map(|entry| {
            let address = entry.get("address").and_then(|v| <&str>::try_from(&**v).ok())?.to_string();
            let prefix = entry.get("prefix").and_then(|v| u32::try_from(&**v).ok()).unwrap_or(0) as u8;
            Some(IpAddress { address, prefix })
        })
        .collect()
}

fn read_routes(value: Option<&OwnedValue>) -> Vec<Route> {
    owned::<Vec<HashMap<String, OwnedValue>>>(value)
        .unwrap_or_default()
        .iter()
        .filter_map(|entry| {
            let str_of = |key: &str| entry.get(key).and_then(|v| <&str>::try_from(&**v).ok()).map(str::to_string);
            Some(Route {
                destination: str_of("dest")?,
                prefix: entry.get("prefix").and_then(|v| u32::try_from(&**v).ok()).unwrap_or(0) as u8,
                gateway: str_of("next-hop").unwrap_or_default(),
                metric: entry.get("metric").and_then(|v| u32::try_from(&**v).ok()).map_or(-1, i64::from),
            })
        })
        .collect()
}

fn read_ip(dict: &SettingsDict, setting: &str) -> IpSettings {
    let v6 = setting == "ipv6";
    let method = match text(dict, setting, "method").as_str() {
        "manual" => IpMethod::Manual,
        "link-local" => IpMethod::LinkLocal,
        "shared" => IpMethod::Shared,
        "disabled" | "ignore" => IpMethod::Disabled,
        "dhcp" => IpMethod::DhcpOnly,
        _ => IpMethod::Auto,
    };
    let mut dns = strings(dict, setting, "dns-data");
    if dns.is_empty() {
        // Before NetworkManager 1.48: v4 as numbers in network order, v6 as 16 bytes
        if v6 {
            for raw in owned::<Vec<Vec<u8>>>(get(dict, setting, "dns")).unwrap_or_default() {
                if let Ok(octets) = <[u8; 16]>::try_from(raw.as_slice()) {
                    dns.push(Ipv6Addr::from(octets).to_string());
                }
            }
        } else {
            for raw in owned::<Vec<u32>>(get(dict, setting, "dns")).unwrap_or_default() {
                dns.push(Ipv4Addr::from(u32::from_be(raw)).to_string());
            }
        }
    }
    IpSettings {
        method,
        addresses: read_addresses(get(dict, setting, "address-data")),
        gateway: text(dict, setting, "gateway"),
        auto_dns: !flag(dict, setting, "ignore-auto-dns", false),
        dns,
        dns_search: strings(dict, setting, "dns-search"),
        auto_routes: !flag(dict, setting, "ignore-auto-routes", false),
        routes: read_routes(get(dict, setting, "route-data")),
        never_default: flag(dict, setting, "never-default", false),
    }
}

fn read_eap(dict: &SettingsDict) -> Eap8021xSettings {
    let s = "802-1x";
    let method = match strings(dict, s, "eap").first().map(String::as_str) {
        Some("tls") => EapMethod::Tls,
        Some("ttls") => EapMethod::Ttls,
        Some("pwd") => EapMethod::Pwd,
        Some("fast") => EapMethod::Fast,
        Some("leap") => EapMethod::Leap,
        _ => EapMethod::Peap,
    };
    let inner = text(dict, s, "phase2-auth");
    let inner = if inner.is_empty() { text(dict, s, "phase2-autheap") } else { inner };
    let ca = bytes(dict, s, "ca-cert");
    Eap8021xSettings {
        method,
        identity: text(dict, s, "identity"),
        anonymous_identity: text(dict, s, "anonymous-identity"),
        ca_certificate: path_from_blob(&ca),
        no_ca_certificate: ca.is_empty() && !flag(dict, s, "system-ca-certs", false) && dict.contains_key(s),
        domain: text(dict, s, "domain-suffix-match"),
        client_certificate: path_from_blob(&bytes(dict, s, "client-cert")),
        private_key: path_from_blob(&bytes(dict, s, "private-key")),
        inner_auth: match inner.as_str() {
            "mschap" => InnerAuth::Mschap,
            "pap" => InnerAuth::Pap,
            "chap" => InnerAuth::Chap,
            "gtc" => InnerAuth::Gtc,
            "md5" => InnerAuth::Md5,
            _ => InnerAuth::Mschapv2,
        },
        pac_file: text(dict, s, "pac-file"),
        peap_version: match text(dict, s, "phase1-peapver").as_str() {
            "0" => 0,
            "1" => 1,
            _ => -1,
        },
    }
}

/// The settings the details editor shows
pub fn read_settings(dict: &SettingsDict) -> ConnectionSettings {
    let assigned = text(dict, "802-11-wireless", "assigned-mac-address");
    let (cloned_mac, cloned_mac_address) = match assigned.as_str() {
        "" => (ClonedMac::Default, String::new()),
        "preserve" => (ClonedMac::Preserve, String::new()),
        "permanent" => (ClonedMac::Permanent, String::new()),
        "random" => (ClonedMac::Random, String::new()),
        "stable" => (ClonedMac::Stable, String::new()),
        "stable-ssid" => (ClonedMac::StableSsid, String::new()),
        address => (ClonedMac::Address, address.to_string()),
    };
    let key_mgmt = text(dict, "802-11-wireless-security", "key-mgmt");
    let security = crate::nmdefs::profile_security(&key_mgmt, &text(dict, "802-11-wireless-security", "auth-alg"), false);
    ConnectionSettings {
        name: text(dict, "connection", "id"),
        autoconnect: flag(dict, "connection", "autoconnect", true),
        metered: match number::<i32>(dict, "connection", "metered").unwrap_or(0) {
            1 | 3 => Metered::Yes,
            2 | 4 => Metered::No,
            _ => Metered::Unknown,
        },
        available_to_all: strings(dict, "connection", "permissions").is_empty(),
        wifi: WifiSettings {
            ssid: bytes(dict, "802-11-wireless", "ssid"),
            hidden: flag(dict, "802-11-wireless", "hidden", false),
            bssid: mac_to_text(&bytes(dict, "802-11-wireless", "bssid")),
            mac_address: mac_to_text(&bytes(dict, "802-11-wireless", "mac-address")),
            cloned_mac,
            cloned_mac_address,
        },
        security: SecuritySettings {
            security,
            wep_key_index: number::<u32>(dict, "802-11-wireless-security", "wep-tx-keyidx").unwrap_or(0) as u8,
            // NM_WEP_KEY_TYPE_PASSPHRASE
            wep_passphrase: number::<u32>(dict, "802-11-wireless-security", "wep-key-type") == Some(2),
            leap_username: text(dict, "802-11-wireless-security", "leap-username"),
            eap: read_eap(dict),
        },
        ip4: read_ip(dict, "ipv4"),
        ip6: read_ip(dict, "ipv6"),
    }
}

/// The secrets of GetSecrets answers (merged over the settings names)
pub fn read_secrets(dict: &SettingsDict) -> Vec<Secret> {
    let mut secrets = Vec::new();
    let mut add = |key, value: String| {
        if !value.is_empty() {
            secrets.push(Secret { key, value });
        }
    };
    let s = "802-11-wireless-security";
    add(SecretKey::WifiPassword, text(dict, s, "psk"));
    let index = number::<u32>(dict, s, "wep-tx-keyidx").unwrap_or(0);
    add(SecretKey::WepKey, text(dict, s, &format!("wep-key{index}")));
    add(SecretKey::LeapPassword, text(dict, s, "leap-password"));
    add(SecretKey::EapPassword, text(dict, "802-1x", "password"));
    add(SecretKey::EapPrivateKeyPassword, text(dict, "802-1x", "private-key-password"));
    secrets
}

// --- Writing ---

fn value<'a>(v: impl Into<Value<'a>>) -> OwnedValue {
    OwnedValue::try_from(v.into()).expect("plain values have no file descriptors")
}

fn set(dict: &mut SettingsDict, setting: &str, key: &str, v: OwnedValue) {
    dict.entry(setting.to_string()).or_default().insert(key.to_string(), v);
}

fn unset(dict: &mut SettingsDict, setting: &str, key: &str) {
    if let Some(props) = dict.get_mut(setting) {
        props.remove(key);
    }
}

fn set_or_unset_text(dict: &mut SettingsDict, setting: &str, key: &str, text: &str) {
    if text.is_empty() {
        unset(dict, setting, key);
    } else {
        set(dict, setting, key, value(text));
    }
}

fn address_list(addresses: &[IpAddress]) -> OwnedValue {
    let list: Vec<HashMap<String, Value>> = addresses
        .iter()
        .map(|a| HashMap::from([("address".to_string(), Value::from(a.address.clone())), ("prefix".to_string(), Value::from(u32::from(a.prefix)))]))
        .collect();
    value(list)
}

fn route_list(routes: &[Route]) -> OwnedValue {
    let list: Vec<HashMap<String, Value>> = routes
        .iter()
        .map(|r| {
            let mut entry = HashMap::from([
                ("dest".to_string(), Value::from(r.destination.clone())),
                ("prefix".to_string(), Value::from(u32::from(r.prefix))),
            ]);
            if !r.gateway.is_empty() {
                entry.insert("next-hop".to_string(), Value::from(r.gateway.clone()));
            }
            if r.metric >= 0 {
                entry.insert("metric".to_string(), Value::from(r.metric as u32));
            }
            entry
        })
        .collect();
    value(list)
}

fn write_ip(dict: &mut SettingsDict, setting: &str, ip: &IpSettings) {
    let v6 = setting == "ipv6";
    let method = match ip.method {
        IpMethod::Auto => "auto",
        IpMethod::DhcpOnly => {
            if v6 { "dhcp" } else { "auto" }
        }
        IpMethod::Manual => "manual",
        IpMethod::LinkLocal => "link-local",
        IpMethod::Shared => "shared",
        IpMethod::Disabled => "disabled",
    };
    set(dict, setting, "method", value(method));
    if ip.method == IpMethod::Manual {
        set(dict, setting, "address-data", address_list(&ip.addresses));
        set_or_unset_text(dict, setting, "gateway", &ip.gateway);
    } else {
        unset(dict, setting, "address-data");
        unset(dict, setting, "gateway");
    }
    // The legacy keys would be read instead of the new ones when both are there
    unset(dict, setting, "addresses");
    unset(dict, setting, "dns");
    set(dict, setting, "ignore-auto-dns", value(!ip.auto_dns));
    set(dict, setting, "dns-data", value(ip.dns.clone()));
    set(dict, setting, "dns-search", value(ip.dns_search.clone()));
    set(dict, setting, "ignore-auto-routes", value(!ip.auto_routes));
    unset(dict, setting, "routes");
    set(dict, setting, "route-data", route_list(&ip.routes));
    set(dict, setting, "never-default", value(ip.never_default));
}

fn write_security(dict: &mut SettingsDict, security: &SecuritySettings) {
    let s = "802-11-wireless-security";
    let key_mgmt = match security.security {
        Security::None => {
            dict.remove(s);
            dict.remove("802-1x");
            return;
        }
        Security::EnhancedOpen => "owe",
        Security::Wep => "none",
        Security::Leap => "ieee8021x",
        Security::WpaPersonal => "wpa-psk",
        Security::Wpa3Personal => "sae",
        Security::WpaEnterprise => "wpa-eap",
        Security::Wpa3Enterprise => "wpa-eap-suite-b-192",
    };
    set(dict, s, "key-mgmt", value(key_mgmt));
    // The secrets of another security type would stay behind after a change of type
    if !matches!(security.security, Security::WpaPersonal | Security::Wpa3Personal) {
        unset(dict, s, "psk");
    }
    if security.security != Security::Wep {
        for key in ["wep-key0", "wep-key1", "wep-key2", "wep-key3", "wep-tx-keyidx", "wep-key-type"] {
            unset(dict, s, key);
        }
    }
    if security.security != Security::Leap {
        unset(dict, s, "leap-username");
        unset(dict, s, "leap-password");
    }
    match security.security {
        Security::Wep => {
            set(dict, s, "wep-tx-keyidx", value(u32::from(security.wep_key_index)));
            set(dict, s, "wep-key-type", value(if security.wep_passphrase { 2u32 } else { 1u32 }));
        }
        Security::Leap => {
            set(dict, s, "auth-alg", value("leap"));
            set(dict, s, "leap-username", value(security.leap_username.as_str()));
        }
        _ => {
            unset(dict, s, "auth-alg");
        }
    }
    if security.security.is_enterprise() {
        write_eap(dict, &security.eap);
    } else {
        dict.remove("802-1x");
    }
}

fn write_eap(dict: &mut SettingsDict, eap: &Eap8021xSettings) {
    let s = "802-1x";
    let method = match eap.method {
        EapMethod::Tls => "tls",
        EapMethod::Peap => "peap",
        EapMethod::Ttls => "ttls",
        EapMethod::Pwd => "pwd",
        EapMethod::Fast => "fast",
        EapMethod::Leap => "leap",
    };
    set(dict, s, "eap", value(vec![method.to_string()]));
    set_or_unset_text(dict, s, "identity", &eap.identity);
    set_or_unset_text(dict, s, "anonymous-identity", &eap.anonymous_identity);
    set_or_unset_text(dict, s, "domain-suffix-match", &eap.domain);
    if eap.ca_certificate.is_empty() {
        unset(dict, s, "ca-cert");
    } else {
        set(dict, s, "ca-cert", value(blob_from_path(&eap.ca_certificate)));
    }
    // Without a CA certificate and without "no CA certificate needed", trust the system's
    set(dict, s, "system-ca-certs", value(eap.ca_certificate.is_empty() && !eap.no_ca_certificate));
    if eap.method == EapMethod::Tls {
        set(dict, s, "client-cert", value(blob_from_path(&eap.client_certificate)));
        set(dict, s, "private-key", value(blob_from_path(&eap.private_key)));
        unset(dict, s, "phase2-auth");
    } else {
        unset(dict, s, "client-cert");
        unset(dict, s, "private-key");
        let inner = match eap.inner_auth {
            InnerAuth::Mschapv2 => "mschapv2",
            InnerAuth::Mschap => "mschap",
            InnerAuth::Pap => "pap",
            InnerAuth::Chap => "chap",
            InnerAuth::Gtc => "gtc",
            InnerAuth::Md5 => "md5",
        };
        if matches!(eap.method, EapMethod::Peap | EapMethod::Ttls | EapMethod::Fast) {
            set(dict, s, "phase2-auth", value(inner));
        }
    }
    if eap.method == EapMethod::Fast {
        set_or_unset_text(dict, s, "pac-file", &eap.pac_file);
    }
    match eap.peap_version {
        0 | 1 if eap.method == EapMethod::Peap => set(dict, s, "phase1-peapver", value(eap.peap_version.to_string())),
        _ => unset(dict, s, "phase1-peapver"),
    }
}

/// Puts the secrets into the profile (they are then kept by NetworkManager, owned by the system)
pub fn write_secrets(dict: &mut SettingsDict, secrets: &[Secret]) {
    let s = "802-11-wireless-security";
    let index = number::<u32>(dict, s, "wep-tx-keyidx").unwrap_or(0);
    for secret in secrets {
        let (setting, key) = match secret.key {
            SecretKey::WifiPassword => (s, "psk".to_string()),
            SecretKey::WepKey => (s, format!("wep-key{index}")),
            SecretKey::LeapPassword => (s, "leap-password".to_string()),
            SecretKey::EapPassword => ("802-1x", "password".to_string()),
            SecretKey::EapPrivateKeyPassword => ("802-1x", "private-key-password".to_string()),
            SecretKey::EapIdentity => ("802-1x", "identity".to_string()),
        };
        set(dict, setting, &key, value(secret.value.as_str()));
    }
}

/// Changes the profile `dict` to `settings`, keeping what Maia does not edit
pub fn apply_settings(dict: &mut SettingsDict, settings: &ConnectionSettings, user: &str) {
    let c = "connection";
    set(dict, c, "id", value(settings.name.as_str()));
    set(dict, c, "autoconnect", value(settings.autoconnect));
    set(
        dict,
        c,
        "metered",
        value(match settings.metered {
            Metered::Unknown => 0i32,
            Metered::Yes => 1,
            Metered::No => 2,
        }),
    );
    let permissions: Vec<String> = if settings.available_to_all { Vec::new() } else { vec![format!("user:{user}:")] };
    set(dict, c, "permissions", value(permissions));

    let w = "802-11-wireless";
    set(dict, w, "ssid", value(settings.wifi.ssid.clone()));
    set(dict, w, "hidden", value(settings.wifi.hidden));
    match mac_from_text(&settings.wifi.bssid) {
        Some(bssid) => set(dict, w, "bssid", value(bssid)),
        None => unset(dict, w, "bssid"),
    }
    match mac_from_text(&settings.wifi.mac_address) {
        Some(mac) => set(dict, w, "mac-address", value(mac)),
        None => unset(dict, w, "mac-address"),
    }
    unset(dict, w, "cloned-mac-address");
    match settings.wifi.cloned_mac {
        ClonedMac::Default => unset(dict, w, "assigned-mac-address"),
        ClonedMac::Preserve => set(dict, w, "assigned-mac-address", value("preserve")),
        ClonedMac::Permanent => set(dict, w, "assigned-mac-address", value("permanent")),
        ClonedMac::Random => set(dict, w, "assigned-mac-address", value("random")),
        ClonedMac::Stable => set(dict, w, "assigned-mac-address", value("stable")),
        ClonedMac::StableSsid => set(dict, w, "assigned-mac-address", value("stable-ssid")),
        ClonedMac::Address => set_or_unset_text(dict, w, "assigned-mac-address", &settings.wifi.cloned_mac_address),
    }
    if settings.security.security != Security::None {
        set(dict, w, "security", value("802-11-wireless-security"));
    } else {
        unset(dict, w, "security");
    }
    write_security(dict, &settings.security);
    write_ip(dict, "ipv4", &settings.ip4);
    write_ip(dict, "ipv6", &settings.ip6);
}

/// A new Wi-Fi profile from settings (hidden and Enterprise networks)
pub fn new_profile(uuid: &str, settings: &ConnectionSettings, secrets: &[Secret], user: &str) -> SettingsDict {
    let mut dict = SettingsDict::new();
    set(&mut dict, "connection", "uuid", value(uuid));
    set(&mut dict, "connection", "type", value("802-11-wireless"));
    set(&mut dict, "802-11-wireless", "mode", value("infrastructure"));
    let mut settings = settings.clone();
    if settings.name.is_empty() {
        settings.name = String::from_utf8_lossy(&settings.wifi.ssid).into_owned();
    }
    apply_settings(&mut dict, &settings, user);
    write_secrets(&mut dict, secrets);
    dict
}

/// The hotspot profile: an access point with WPA2 (CCMP when the adapter has RSN), shared IPv4,
/// not started by itself, bound to its adapter
pub fn hotspot_profile(uuid: &str, interface: &str, ssid: &str, password: &str, rsn: bool) -> SettingsDict {
    let mut dict = SettingsDict::new();
    let c = "connection";
    set(&mut dict, c, "uuid", value(uuid));
    set(&mut dict, c, "id", value("Hotspot"));
    set(&mut dict, c, "type", value("802-11-wireless"));
    set(&mut dict, c, "autoconnect", value(false));
    set(&mut dict, c, "interface-name", value(interface));
    let w = "802-11-wireless";
    set(&mut dict, w, "ssid", value(ssid.as_bytes().to_vec()));
    set(&mut dict, w, "mode", value("ap"));
    set(&mut dict, w, "security", value("802-11-wireless-security"));
    let s = "802-11-wireless-security";
    set(&mut dict, s, "key-mgmt", value("wpa-psk"));
    set(&mut dict, s, "psk", value(password));
    let (proto, cipher) = if rsn { ("rsn", "ccmp") } else { ("wpa", "tkip") };
    set(&mut dict, s, "proto", value(vec![proto.to_string()]));
    set(&mut dict, s, "pairwise", value(vec![cipher.to_string()]));
    set(&mut dict, s, "group", value(vec![cipher.to_string()]));
    set(&mut dict, "ipv4", "method", value("shared"));
    set(&mut dict, "ipv6", "method", value("ignore"));
    dict
}

/// 8 characters for a hotspot password, without the ones easily mistaken (0 O 1 l I)
pub fn generated_password() -> String {
    const ALPHABET: &[u8] = b"abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let random = uuid::Uuid::new_v4();
    random.as_bytes()[..8].iter().map(|b| ALPHABET[*b as usize % ALPHABET.len()] as char).collect()
}

/// The secret a security type asks for, for checks before saving
pub fn has_secret_for(security: Security, secrets: &[Secret]) -> bool {
    match security {
        Security::WpaPersonal | Security::Wpa3Personal => find_secret(secrets, SecretKey::WifiPassword).is_some(),
        Security::Wep => find_secret(secrets, SecretKey::WepKey).is_some(),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn editable() -> ConnectionSettings {
        let mut s = ConnectionSettings { name: "Lab".into(), ..Default::default() };
        s.wifi.ssid = b"Lab".to_vec();
        s.wifi.bssid = "0A:00:00:00:00:01".into();
        s.wifi.cloned_mac = ClonedMac::Random;
        s.security.security = Security::WpaPersonal;
        s.metered = Metered::Yes;
        s.ip4 = IpSettings {
            method: IpMethod::Manual,
            addresses: vec![IpAddress { address: "192.168.7.20".into(), prefix: 24 }],
            gateway: "192.168.7.1".into(),
            auto_dns: false,
            dns: vec!["1.1.1.1".into()],
            dns_search: vec!["lab.example".into()],
            auto_routes: true,
            routes: vec![Route { destination: "10.0.0.0".into(), prefix: 8, gateway: "192.168.7.254".into(), metric: 50 }],
            never_default: true,
        };
        s.ip6.method = IpMethod::DhcpOnly;
        s
    }

    #[test]
    fn settings_survive_a_round_trip() {
        let settings = editable();
        let dict = new_profile("u1", &settings, &[], "kubuntu");
        let read = read_settings(&dict);
        assert_eq!(read, ConnectionSettings { available_to_all: false, ..settings });
    }

    #[test]
    fn editing_keeps_what_maia_does_not_know() {
        let mut dict = new_profile("u1", &editable(), &[], "kubuntu");
        set(&mut dict, "802-11-wireless", "powersave", value(2u32));
        let mut changed = editable();
        changed.autoconnect = false;
        changed.ip4.method = IpMethod::Auto;
        apply_settings(&mut dict, &changed, "kubuntu");
        assert_eq!(number::<u32>(&dict, "802-11-wireless", "powersave"), Some(2));
        let read = read_settings(&dict);
        assert!(!read.autoconnect);
        assert_eq!(read.ip4.method, IpMethod::Auto);
        assert!(read.ip4.addresses.is_empty(), "no manual addresses with DHCP");
    }

    #[test]
    fn enterprise_profiles_carry_their_eap_details() {
        let mut settings = editable();
        settings.security.security = Security::WpaEnterprise;
        settings.security.eap = Eap8021xSettings {
            method: EapMethod::Ttls,
            identity: "jan".into(),
            ca_certificate: "/etc/ssl/corp.pem".into(),
            inner_auth: InnerAuth::Pap,
            ..Default::default()
        };
        let secrets = [Secret { key: SecretKey::EapPassword, value: "secret".into() }];
        let dict = new_profile("u2", &settings, &secrets, "kubuntu");
        let read = read_settings(&dict);
        assert_eq!(read.security.eap.method, EapMethod::Ttls);
        assert_eq!(read.security.eap.ca_certificate, "/etc/ssl/corp.pem");
        assert_eq!(read.security.eap.inner_auth, InnerAuth::Pap);
        assert_eq!(read_secrets(&dict), secrets.to_vec());
    }

    #[test]
    fn the_hotspot_is_an_access_point_with_shared_ipv4() {
        let dict = hotspot_profile("u3", "wlan0", "maia", "abcd2345", true);
        assert_eq!(text(&dict, "802-11-wireless", "mode"), "ap");
        assert_eq!(text(&dict, "ipv4", "method"), "shared");
        assert_eq!(read_secrets(&dict), vec![Secret { key: SecretKey::WifiPassword, value: "abcd2345".into() }]);
        let password = generated_password();
        assert_eq!(password.len(), 8);
        assert!(!password.contains(['0', 'O', '1', 'l', 'I']));
    }

    #[test]
    fn legacy_dns_is_read_when_there_is_no_dns_data() {
        let mut dict = SettingsDict::new();
        set(&mut dict, "ipv4", "dns", value(vec![u32::from(Ipv4Addr::new(9, 9, 9, 9)).to_be()]));
        assert_eq!(read_ip(&dict, "ipv4").dns, vec!["9.9.9.9".to_string()]);
    }
}
