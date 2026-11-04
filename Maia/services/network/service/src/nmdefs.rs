//! NetworkManager's numbers and how they map to the model: device states and reasons, access point
//! flags, adapter capabilities, connectivity. Pure functions, tested without NetworkManager.
//!
//! The values are those of nm-dbus-interface.h (NetworkManager 1.54); GNOME's panel-common.c and
//! network.js read the same ones.

use crate::model::{BAND_2_4_GHZ, BAND_5_GHZ, BAND_6_GHZ, Connectivity, DeviceState, Permission, Security, StateReason, WifiMode};

pub const DEVICE_TYPE_WIFI: u32 = 2;

pub const DEVICE_STATE_NEED_AUTH: u32 = 60;
pub const DEVICE_STATE_ACTIVATED: u32 = 100;
pub const DEVICE_STATE_FAILED: u32 = 120;

pub fn device_state(state: u32) -> DeviceState {
    match state {
        10 => DeviceState::Unmanaged,
        20 => DeviceState::Unavailable,
        30 => DeviceState::Disconnected,
        40 | 50 | 70 | 80 | 90 => DeviceState::Connecting,
        60 => DeviceState::NeedAuth,
        100 => DeviceState::Connected,
        110 => DeviceState::Disconnecting,
        120 => DeviceState::Failed,
        _ => DeviceState::Unknown,
    }
}

pub const REASON_NO_SECRETS: u32 = 7;

pub fn state_reason(reason: u32) -> StateReason {
    match reason {
        0 => StateReason::None,
        4 => StateReason::ConfigFailed,
        5 | 15 | 16 | 17 => StateReason::IpConfigFailed,
        6 => StateReason::IpConfigExpired,
        7 => StateReason::NoSecrets,
        8 => StateReason::WrongSecrets,
        9 | 10 => StateReason::SupplicantFailed,
        11 => StateReason::SupplicantTimeout,
        35 => StateReason::FirmwareMissing,
        38 => StateReason::ConnectionRemoved,
        39 => StateReason::UserRequested,
        40 => StateReason::CarrierLost,
        53 => StateReason::SsidNotFound,
        _ => StateReason::Other,
    }
}

pub fn connectivity(value: u32) -> Connectivity {
    match value {
        1 => Connectivity::None,
        2 => Connectivity::Portal,
        3 => Connectivity::Limited,
        4 => Connectivity::Full,
        _ => Connectivity::Unknown,
    }
}

/// GetPermissions values: "yes", "auth", "no"
pub fn permission(value: &str) -> Permission {
    match value {
        "yes" => Permission::Yes,
        "auth" => Permission::Auth,
        _ => Permission::No,
    }
}

pub fn wifi_mode(mode: u32) -> WifiMode {
    match mode {
        1 => WifiMode::Adhoc,
        3 => WifiMode::AccessPoint,
        _ => WifiMode::Infrastructure,
    }
}

// Access point flags (NM80211ApFlags) and security flags (NM80211ApSecurityFlags)
const AP_FLAG_PRIVACY: u32 = 0x1;
pub const AP_FLAG_WPS_PBC: u32 = 0x4;
const SEC_KEY_MGMT_PSK: u32 = 0x100;
const SEC_KEY_MGMT_8021X: u32 = 0x200;
const SEC_KEY_MGMT_SAE: u32 = 0x400;
const SEC_KEY_MGMT_OWE: u32 = 0x800;
const SEC_KEY_MGMT_OWE_TM: u32 = 0x1000;
const SEC_KEY_MGMT_EAP_SUITE_B_192: u32 = 0x2000;

/// The security of an access point. For mixed modes the strongest one, as GNOME picks it
/// (WPA2/WPA3 transition networks are WPA3 Personal).
pub fn ap_security(flags: u32, wpa_flags: u32, rsn_flags: u32) -> Security {
    let both = wpa_flags | rsn_flags;
    if rsn_flags & (SEC_KEY_MGMT_OWE | SEC_KEY_MGMT_OWE_TM) != 0 {
        Security::EnhancedOpen
    } else if both & SEC_KEY_MGMT_8021X != 0 || rsn_flags & SEC_KEY_MGMT_EAP_SUITE_B_192 != 0 {
        if rsn_flags & SEC_KEY_MGMT_EAP_SUITE_B_192 != 0 { Security::Wpa3Enterprise } else { Security::WpaEnterprise }
    } else if rsn_flags & SEC_KEY_MGMT_SAE != 0 {
        Security::Wpa3Personal
    } else if both & SEC_KEY_MGMT_PSK != 0 {
        Security::WpaPersonal
    } else if flags & AP_FLAG_PRIVACY != 0 {
        Security::Wep
    } else {
        Security::None
    }
}

/// The security of a saved profile, from its 802-11-wireless-security settings
pub fn profile_security(key_mgmt: &str, auth_alg: &str, eap_suite_b: bool) -> Security {
    match key_mgmt {
        "" => Security::None,
        "owe" => Security::EnhancedOpen,
        "none" => Security::Wep,
        "ieee8021x" if auth_alg == "leap" => Security::Leap,
        "ieee8021x" => Security::WpaEnterprise,
        "wpa-psk" => Security::WpaPersonal,
        "sae" => Security::Wpa3Personal,
        "wpa-eap" | "wpa-eap-suite-b-192" if eap_suite_b || key_mgmt == "wpa-eap-suite-b-192" => Security::Wpa3Enterprise,
        "wpa-eap" => Security::WpaEnterprise,
        _ => Security::None,
    }
}

// Wi-Fi device capabilities (NMDeviceWifiCapabilities)
/// WPA2/RSN (the hotspot uses CCMP with it)
pub const WIFI_CAP_RSN: u32 = 0x20;
const WIFI_CAP_AP: u32 = 0x40;
const WIFI_CAP_FREQ_VALID: u32 = 0x100;
const WIFI_CAP_FREQ_2GHZ: u32 = 0x200;
const WIFI_CAP_FREQ_5GHZ: u32 = 0x400;
const WIFI_CAP_FREQ_6GHZ: u32 = 0x800;

pub fn bands(capabilities: u32) -> u8 {
    if capabilities & WIFI_CAP_FREQ_VALID == 0 {
        return BAND_2_4_GHZ;
    }
    let mut bands = 0;
    if capabilities & WIFI_CAP_FREQ_2GHZ != 0 {
        bands |= BAND_2_4_GHZ;
    }
    if capabilities & WIFI_CAP_FREQ_5GHZ != 0 {
        bands |= BAND_5_GHZ;
    }
    if capabilities & WIFI_CAP_FREQ_6GHZ != 0 {
        bands |= BAND_6_GHZ;
    }
    bands
}

pub fn can_hotspot(capabilities: u32) -> bool {
    capabilities & WIFI_CAP_AP != 0
}

// GetSecrets flags (NMSecretAgentGetSecretsFlags)
pub const SECRETS_ALLOW_INTERACTION: u32 = 0x1;
pub const SECRETS_REQUEST_NEW: u32 = 0x2;
pub const SECRETS_WPS_PBC_ACTIVE: u32 = 0x8;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn access_point_security() {
        assert_eq!(ap_security(0, 0, 0), Security::None);
        assert_eq!(ap_security(AP_FLAG_PRIVACY, 0, 0), Security::Wep);
        assert_eq!(ap_security(AP_FLAG_PRIVACY, 0, SEC_KEY_MGMT_PSK), Security::WpaPersonal);
        assert_eq!(ap_security(AP_FLAG_PRIVACY, 0, SEC_KEY_MGMT_PSK | SEC_KEY_MGMT_SAE), Security::Wpa3Personal);
        assert_eq!(ap_security(AP_FLAG_PRIVACY, SEC_KEY_MGMT_8021X, SEC_KEY_MGMT_8021X), Security::WpaEnterprise);
        assert_eq!(ap_security(0, 0, SEC_KEY_MGMT_OWE), Security::EnhancedOpen);
    }

    #[test]
    fn capabilities_of_this_machine() {
        // WirelessCapabilities of an Intel AX201 under NetworkManager 1.54
        assert_eq!(bands(12287), BAND_2_4_GHZ | BAND_5_GHZ | BAND_6_GHZ);
        assert!(can_hotspot(12287));
    }

    #[test]
    fn states_and_reasons() {
        assert_eq!(device_state(70), DeviceState::Connecting);
        assert_eq!(device_state(60), DeviceState::NeedAuth);
        assert_eq!(state_reason(8), StateReason::WrongSecrets);
        assert_eq!(state_reason(999), StateReason::Other);
    }

    #[test]
    fn profile_security_from_key_management() {
        assert_eq!(profile_security("wpa-psk", "", false), Security::WpaPersonal);
        assert_eq!(profile_security("ieee8021x", "leap", false), Security::Leap);
        assert_eq!(profile_security("wpa-eap-suite-b-192", "", false), Security::Wpa3Enterprise);
    }
}
