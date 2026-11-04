//! The secret agent of the session: NetworkManager asks it for passwords.
//!
//! When a connection needs secrets NetworkManager does not have (a new network, a refused password,
//! an Enterprise identity), it calls GetSecrets on the registered agents. This agent turns the
//! request into a SecretRequest (which fields, how to check them), asks the user through the
//! Prompter (the shell shows its password dialog, see prompt.rs) and returns the answer.
//!
//! Secrets are not stored here: NetworkManager saves what the agent returns into the profile
//! (secrets owned by the system, a file only root can read), as `nmcli` does. KWallet is off in
//! Maia, so there is no other store; SaveSecrets and DeleteSecrets have nothing to do. The KDE agent
//! (kded module networkmanagement) is kept from loading in Maia sessions
//! (Maia/DeployFiles/etc/xdg/kded6rc), so that only this one answers.
//!
//! Errors NetworkManager understands: UserCanceled (the user closed the dialog: the attempt ends
//! with "no secrets", without a failure message), NoSecrets (asked without interaction).

use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

use crate::nmdefs;
use crate::prompt::Prompter;
use crate::settings::{EapMethod, SecretKey, SecretReply, SecretRequest, secret_fields};

pub const PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
pub const IDENTIFIER: &str = "org.maia.network";

type Props = HashMap<String, OwnedValue>;
type SettingsDict = HashMap<String, HashMap<String, OwnedValue>>;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    UserCanceled(String),
    NoSecrets(String),
}

pub struct Agent {
    prompter: Prompter,
    next: AtomicU64,
    /// Open requests by (connection path, setting name), for CancelGetSecrets
    open: Mutex<HashMap<(String, String), String>>,
}

impl Agent {
    pub fn new(prompter: Prompter) -> Agent {
        Agent { prompter, next: AtomicU64::new(0), open: Mutex::new(HashMap::new()) }
    }
}

fn text(props: Option<&Props>, key: &str) -> String {
    props.and_then(|p| p.get(key)).and_then(|v| <&str>::try_from(&**v).ok()).map(str::to_string).unwrap_or_default()
}

fn number(props: Option<&Props>, key: &str) -> u32 {
    props.and_then(|p| p.get(key)).and_then(|v| u32::try_from(&**v).ok()).unwrap_or(0)
}

fn eap_method(dict: &SettingsDict) -> Option<EapMethod> {
    let methods: Vec<String> = dict
        .get("802-1x")
        .and_then(|p| p.get("eap"))
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<String>::try_from(v).ok())
        .unwrap_or_default();
    methods.first().map(|m| match m.as_str() {
        "tls" => EapMethod::Tls,
        "ttls" => EapMethod::Ttls,
        "pwd" => EapMethod::Pwd,
        "fast" => EapMethod::Fast,
        "leap" => EapMethod::Leap,
        _ => EapMethod::Peap,
    })
}

/// What to ask the user for a GetSecrets call
pub fn request_for(id: String, dict: &SettingsDict, setting_name: &str, flags: u32) -> SecretRequest {
    let connection = dict.get("connection");
    let security_setting = dict.get("802-11-wireless-security");
    let eap = eap_method(dict);
    let mut security = nmdefs::profile_security(&text(security_setting, "key-mgmt"), &text(security_setting, "auth-alg"), false);
    if setting_name == "802-1x" && !security.is_enterprise() {
        security = crate::model::Security::WpaEnterprise;
    }
    // NM_WEP_KEY_TYPE_PASSPHRASE
    let wep_passphrase = number(security_setting, "wep-key-type") == 2;
    let mut fields = secret_fields(security, eap, wep_passphrase);
    let identity = text(dict.get("802-1x"), "identity");
    for field in &mut fields {
        if field.key == SecretKey::EapIdentity {
            field.value = identity.clone();
        }
    }
    let ssid = dict
        .get("802-11-wireless")
        .and_then(|p| p.get("ssid"))
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<u8>::try_from(v).ok())
        .map(|ssid| String::from_utf8_lossy(&ssid).into_owned())
        .unwrap_or_default();
    let name = if ssid.is_empty() { text(connection, "id") } else { ssid };
    SecretRequest {
        id,
        connection_uuid: text(connection, "uuid"),
        name,
        device_id: String::new(),
        security,
        fields,
        retry: flags & nmdefs::SECRETS_REQUEST_NEW != 0,
        wps_push_button: flags & nmdefs::SECRETS_WPS_PBC_ACTIVE != 0,
    }
}

/// The answer as NetworkManager wants it: setting -> key -> value
pub fn secrets_dict(dict: &SettingsDict, secrets: &[crate::settings::Secret]) -> SettingsDict {
    let wep_index = number(dict.get("802-11-wireless-security"), "wep-tx-keyidx");
    let mut out: SettingsDict = HashMap::new();
    for secret in secrets {
        let (setting, key) = match secret.key {
            SecretKey::WifiPassword => ("802-11-wireless-security", "psk".to_string()),
            SecretKey::WepKey => ("802-11-wireless-security", format!("wep-key{wep_index}")),
            SecretKey::LeapPassword => ("802-11-wireless-security", "leap-password".to_string()),
            SecretKey::EapPassword => ("802-1x", "password".to_string()),
            SecretKey::EapPrivateKeyPassword => ("802-1x", "private-key-password".to_string()),
            SecretKey::EapIdentity => ("802-1x", "identity".to_string()),
        };
        if let Ok(value) = OwnedValue::try_from(Value::from(secret.value.as_str())) {
            out.entry(setting.to_string()).or_default().insert(key, value);
        }
    }
    out
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl Agent {
    async fn get_secrets(
        &self,
        connection: SettingsDict,
        connection_path: OwnedObjectPath,
        setting_name: String,
        _hints: Vec<String>,
        flags: u32,
    ) -> Result<SettingsDict, AgentError> {
        if flags & nmdefs::SECRETS_ALLOW_INTERACTION == 0 {
            // This agent keeps nothing: without asking the user it has nothing to give
            return Err(AgentError::NoSecrets("no stored secrets".into()));
        }
        let id = format!("nm-{}", self.next.fetch_add(1, Ordering::Relaxed) + 1);
        let request = request_for(id.clone(), &connection, &setting_name, flags);
        if request.fields.is_empty() {
            return Err(AgentError::NoSecrets(format!("nothing to ask for {setting_name}")));
        }
        let key = (connection_path.to_string(), setting_name.clone());
        self.open.lock().expect("lock").insert(key.clone(), id.clone());
        let reply = self.prompter.ask(request).await;
        self.open.lock().expect("lock").remove(&key);
        match reply {
            SecretReply::Cancelled => Err(AgentError::UserCanceled("the user cancelled".into())),
            SecretReply::Secrets(secrets) => Ok(secrets_dict(&connection, &secrets)),
        }
    }

    async fn cancel_get_secrets(&self, connection_path: OwnedObjectPath, setting_name: String) {
        let id = self.open.lock().expect("lock").remove(&(connection_path.to_string(), setting_name));
        if let Some(id) = id {
            self.prompter.cancel(&id);
        }
    }

    async fn save_secrets(&self, _connection: SettingsDict, _connection_path: OwnedObjectPath) {}

    async fn delete_secrets(&self, _connection: SettingsDict, _connection_path: OwnedObjectPath) {}
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Security;
    use crate::settings::{Secret, Validation};

    fn value<'a, T: Into<Value<'a>>>(v: T) -> OwnedValue {
        OwnedValue::try_from(v.into()).unwrap()
    }

    fn personal() -> SettingsDict {
        let mut dict = SettingsDict::new();
        let mut c = Props::new();
        c.insert("id".into(), value("Home"));
        c.insert("uuid".into(), value("u1"));
        dict.insert("connection".into(), c);
        let mut w = Props::new();
        w.insert("ssid".into(), value(b"Home".to_vec()));
        dict.insert("802-11-wireless".into(), w);
        let mut s = Props::new();
        s.insert("key-mgmt".into(), value("wpa-psk"));
        dict.insert("802-11-wireless-security".into(), s);
        dict
    }

    #[test]
    fn a_personal_network_asks_for_its_password() {
        let request = request_for("nm-1".into(), &personal(), "802-11-wireless-security", nmdefs::SECRETS_ALLOW_INTERACTION);
        assert_eq!(request.name, "Home");
        assert_eq!(request.security, Security::WpaPersonal);
        assert_eq!(request.fields.len(), 1);
        assert_eq!(request.fields[0].validation, Validation::WpaPassword);
        assert!(!request.retry);
        let retry = request_for("nm-2".into(), &personal(), "802-11-wireless-security", nmdefs::SECRETS_REQUEST_NEW);
        assert!(retry.retry, "a refused password asks again");
    }

    #[test]
    fn the_answer_goes_into_the_right_settings() {
        let dict = secrets_dict(&personal(), &[Secret { key: SecretKey::WifiPassword, value: "12345678".into() }]);
        let psk = &dict["802-11-wireless-security"]["psk"];
        assert_eq!(<&str>::try_from(&**psk).unwrap(), "12345678");
    }
}
