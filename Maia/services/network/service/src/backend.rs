//! What a backend (NetworkManager, or the fake one for tests) and the rest of the service exchange.
//!
//! A backend runs as one task: it sends `BackendEvent`s about the state and executes the
//! `Command`s it receives, answering each through its `reply` channel. Both directions are
//! channels, so the RPC side never waits for NetworkManager, and tests drive the service with the
//! fake backend (fake.rs).
//!
//! When a connection needs secrets, the backend asks through a `Prompter` (prompt.rs): the hub
//! forwards the request to the shell that registered as SecretPrompter.

use tokio::sync::oneshot;

use crate::model::{AccessPoint, Event, SavedConnection, Security, Status, WifiDevice};
use crate::settings::{ConnectionSettings, Secret};

/// What the backend tells the rest of the service
#[derive(Debug)]
pub enum BackendEvent {
    Status(Status),
    /// A Wi-Fi device appeared or changed: its whole state
    Device(WifiDevice),
    DeviceRemoved(String),
    /// Everything the device sees now (sent again whenever an access point changes)
    AccessPoints { device_id: String, access_points: Vec<AccessPoint> },
    /// A saved Wi-Fi profile appeared or changed
    Connection(SavedConnection),
    ConnectionRemoved(String),
    Event(Event),
}

/// Contract ErrorCode
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    NotFound,
    NotAllowed,
    InvalidArgument,
    NotSupported,
    Unavailable,
    Failed,
}

/// A failed command; `message` is for logs, not for people
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpError {
    pub code: ErrorCode,
    pub message: String,
}

impl OpError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }
}

pub type OpResult<T = ()> = Result<T, OpError>;

pub type Reply<T = ()> = oneshot::Sender<OpResult<T>>;

/// Hotspot password: generated (8 random characters) or given
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HotspotPassword {
    Generate,
    Given(String),
}

/// What the rest of the service asks the backend to do. The hub has resolved network ids already.
#[derive(Debug)]
pub enum Command {
    SetWirelessEnabled { enabled: bool, reply: Reply },
    /// device_id "" = every Wi-Fi device
    RequestScan { device_id: String, reply: Reply },
    /// A visible network: with `connection_uuid` when a profile fits it, else a new profile made
    /// from the strongest access point `bssid`
    ConnectNetwork {
        device_id: String,
        ssid: Vec<u8>,
        security: Security,
        bssid: String,
        connection_uuid: Option<String>,
        reply: Reply,
    },
    Activate { uuid: String, device_id: String, reply: Reply },
    ConnectWithSettings { device_id: String, settings: ConnectionSettings, secrets: Vec<Secret>, reply: Reply<String> },
    Disconnect { device_id: String, reply: Reply },
    Forget { uuid: String, reply: Reply },
    Settings { uuid: String, reply: Reply<ConnectionSettings> },
    UpdateSettings { uuid: String, settings: ConnectionSettings, secrets: Vec<Secret>, reply: Reply },
    Secrets { uuid: String, reply: Reply<Vec<Secret>> },
    /// Returns the profile UUID and the password in use
    StartHotspot { device_id: String, ssid: String, password: HotspotPassword, reply: Reply<(String, String)> },
    StopHotspot { device_id: String, reply: Reply },
    CheckConnectivity { reply: Reply },
}
