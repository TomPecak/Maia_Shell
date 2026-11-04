//! Settings and secrets of a connection, and password requests: plain values mirroring the
//! contract (ConnectionSettings, Secret, SecretRequest), plus the checks a password must pass.

use crate::model::{IpAddress, Metered, Security};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum IpMethod {
    #[default]
    Auto,
    DhcpOnly,
    Manual,
    LinkLocal,
    Shared,
    Disabled,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Route {
    pub destination: String,
    pub prefix: u8,
    pub gateway: String,
    /// -1 = default
    pub metric: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IpSettings {
    pub method: IpMethod,
    pub addresses: Vec<IpAddress>,
    pub gateway: String,
    pub auto_dns: bool,
    pub dns: Vec<String>,
    pub dns_search: Vec<String>,
    pub auto_routes: bool,
    pub routes: Vec<Route>,
    pub never_default: bool,
}

impl Default for IpSettings {
    fn default() -> Self {
        Self {
            method: IpMethod::Auto,
            addresses: Vec::new(),
            gateway: String::new(),
            auto_dns: true,
            dns: Vec::new(),
            dns_search: Vec::new(),
            auto_routes: true,
            routes: Vec::new(),
            never_default: false,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ClonedMac {
    #[default]
    Default,
    Preserve,
    Permanent,
    Random,
    Stable,
    StableSsid,
    Address,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WifiSettings {
    pub ssid: Vec<u8>,
    pub hidden: bool,
    pub bssid: String,
    pub mac_address: String,
    pub cloned_mac: ClonedMac,
    pub cloned_mac_address: String,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum EapMethod {
    Tls,
    #[default]
    Peap,
    Ttls,
    Pwd,
    Fast,
    Leap,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum InnerAuth {
    #[default]
    Mschapv2,
    Mschap,
    Pap,
    Chap,
    Gtc,
    Md5,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Eap8021xSettings {
    pub method: EapMethod,
    pub identity: String,
    pub anonymous_identity: String,
    pub ca_certificate: String,
    pub no_ca_certificate: bool,
    pub domain: String,
    pub client_certificate: String,
    pub private_key: String,
    pub inner_auth: InnerAuth,
    pub pac_file: String,
    /// -1 = automatic
    pub peap_version: i8,
}

impl Default for Eap8021xSettings {
    fn default() -> Self {
        Self {
            method: EapMethod::Peap,
            identity: String::new(),
            anonymous_identity: String::new(),
            ca_certificate: String::new(),
            no_ca_certificate: false,
            domain: String::new(),
            client_certificate: String::new(),
            private_key: String::new(),
            inner_auth: InnerAuth::Mschapv2,
            pac_file: String::new(),
            peap_version: -1,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SecuritySettings {
    pub security: Security,
    pub wep_key_index: u8,
    pub wep_passphrase: bool,
    pub leap_username: String,
    pub eap: Eap8021xSettings,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConnectionSettings {
    pub name: String,
    pub autoconnect: bool,
    pub metered: Metered,
    pub available_to_all: bool,
    pub wifi: WifiSettings,
    pub security: SecuritySettings,
    pub ip4: IpSettings,
    pub ip6: IpSettings,
}

impl Default for ConnectionSettings {
    fn default() -> Self {
        Self {
            name: String::new(),
            autoconnect: true,
            metered: Metered::Unknown,
            available_to_all: false,
            wifi: WifiSettings::default(),
            security: SecuritySettings::default(),
            ip4: IpSettings::default(),
            ip6: IpSettings::default(),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SecretKey {
    WifiPassword,
    WepKey,
    LeapPassword,
    EapPassword,
    EapPrivateKeyPassword,
    EapIdentity,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Secret {
    pub key: SecretKey,
    pub value: String,
}

pub fn find_secret(secrets: &[Secret], key: SecretKey) -> Option<&str> {
    secrets.iter().find(|s| s.key == key).map(|s| s.value.as_str())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Validation {
    NotEmpty,
    WpaPassword,
    WepKey,
    WepPassphrase,
}

impl Validation {
    /// Whether `value` passes, the same rules as GNOME's password dialog
    pub fn accepts(self, value: &str) -> bool {
        let hex = |s: &str| s.chars().all(|c| c.is_ascii_hexdigit());
        match self {
            Validation::NotEmpty => !value.is_empty(),
            Validation::WpaPassword => {
                let n = value.chars().count();
                (8..=63).contains(&n) || (value.len() == 64 && hex(value))
            }
            Validation::WepKey => {
                let n = value.len();
                ((n == 10 || n == 26) && hex(value)) || ((n == 5 || n == 13) && value.is_ascii())
            }
            Validation::WepPassphrase => (1..=64).contains(&value.chars().count()),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecretField {
    pub key: SecretKey,
    pub value: String,
    pub hidden: bool,
    pub validation: Validation,
}

/// The fields a dialog needs for a connection of `security` (`eap` for the Enterprise method)
pub fn secret_fields(security: Security, eap: Option<EapMethod>, wep_passphrase: bool) -> Vec<SecretField> {
    let field = |key, hidden, validation| SecretField { key, value: String::new(), hidden, validation };
    match security {
        Security::None | Security::EnhancedOpen => Vec::new(),
        Security::WpaPersonal | Security::Wpa3Personal => {
            vec![field(SecretKey::WifiPassword, true, Validation::WpaPassword)]
        }
        Security::Wep => vec![field(
            SecretKey::WepKey,
            true,
            if wep_passphrase { Validation::WepPassphrase } else { Validation::WepKey },
        )],
        Security::Leap => vec![field(SecretKey::LeapPassword, true, Validation::NotEmpty)],
        Security::WpaEnterprise | Security::Wpa3Enterprise => match eap.unwrap_or_default() {
            EapMethod::Tls => vec![
                field(SecretKey::EapIdentity, false, Validation::NotEmpty),
                field(SecretKey::EapPrivateKeyPassword, true, Validation::NotEmpty),
            ],
            _ => vec![
                field(SecretKey::EapIdentity, false, Validation::NotEmpty),
                field(SecretKey::EapPassword, true, Validation::NotEmpty),
            ],
        },
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecretRequest {
    pub id: String,
    pub connection_uuid: String,
    pub name: String,
    pub device_id: String,
    pub security: Security,
    pub fields: Vec<SecretField>,
    pub retry: bool,
    pub wps_push_button: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SecretReply {
    Cancelled,
    Secrets(Vec<Secret>),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wpa_passwords_follow_the_standard() {
        assert!(!Validation::WpaPassword.accepts("1234567"));
        assert!(Validation::WpaPassword.accepts("12345678"));
        assert!(Validation::WpaPassword.accepts(&"a".repeat(63)));
        assert!(!Validation::WpaPassword.accepts(&"a".repeat(65)));
        assert!(Validation::WpaPassword.accepts(&"0123456789abcdef".repeat(4)), "64 hex digits");
        assert!(!Validation::WpaPassword.accepts(&"g".repeat(64)), "64 characters that are not hex");
        assert!(Validation::WpaPassword.accepts("zażółćgęś"), "counted in characters, not bytes");
    }

    #[test]
    fn wep_keys_have_fixed_lengths() {
        assert!(Validation::WepKey.accepts("abcde"));
        assert!(Validation::WepKey.accepts("0123456789"));
        assert!(!Validation::WepKey.accepts("012345678z"));
        assert!(!Validation::WepKey.accepts("abcdef"));
    }

    #[test]
    fn enterprise_asks_identity_and_the_right_secret() {
        let peap = secret_fields(Security::WpaEnterprise, Some(EapMethod::Peap), false);
        assert_eq!(peap.iter().map(|f| f.key).collect::<Vec<_>>(), vec![SecretKey::EapIdentity, SecretKey::EapPassword]);
        let tls = secret_fields(Security::WpaEnterprise, Some(EapMethod::Tls), false);
        assert_eq!(tls[1].key, SecretKey::EapPrivateKeyPassword);
        assert!(secret_fields(Security::EnhancedOpen, None, false).is_empty());
    }
}
