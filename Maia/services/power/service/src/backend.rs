//! What the sources and the rest of the service exchange.
//!
//! A backend (the system's services, or the fake) sends `BackendEvent`s with the whole state of what
//! changed, and carries out the `Command`s it gets. Both directions are channels, so the Cap'n Proto
//! side never waits for D-Bus or sysfs, and the tests drive the service with the fake backend.

use tokio::sync::{mpsc, oneshot};

use crate::model::{Battery, Display, KeyboardBacklight, PowerStatus, Profile, Profiles};

#[derive(Clone, Debug, PartialEq)]
pub enum BackendEvent {
    Status(PowerStatus),
    Battery(Battery),
    BatteryRemoved(String),
    Display(Display),
    DisplayRemoved(String),
    Keyboard(KeyboardBacklight),
    Profiles(Profiles),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    NotFound,
    NotAllowed,
    InvalidArgument,
    NotSupported,
    Unavailable,
    Failed,
}

/// Why a command failed; message is for logs
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpError {
    pub code: ErrorCode,
    pub message: String,
}

impl OpError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> OpError {
        OpError { code, message: message.into() }
    }
}

pub type Reply<T = ()> = oneshot::Sender<Result<T, OpError>>;

#[derive(Debug)]
pub enum Command {
    /// A raw value already checked against the display's range
    SetBrightness { display_id: String, raw: u32, reply: Reply },
    SetKeyboardBrightness { raw: u32, reply: Reply },
    SetProfile { profile: Profile, reply: Reply },
    /// Answers with a cookie for ReleaseProfile
    HoldProfile { profile: Profile, reason: String, application_id: String, reply: Reply<u32> },
    ReleaseProfile { cookie: u32 },
}

/// Where each kind of command goes: the system backend has a task per source, the fake one task
#[derive(Clone)]
pub struct Commands {
    pub brightness: mpsc::UnboundedSender<Command>,
    pub keyboard: mpsc::UnboundedSender<Command>,
    pub profiles: mpsc::UnboundedSender<Command>,
}

impl Commands {
    /// One channel for everything (the fake backend)
    pub fn single() -> (Commands, mpsc::UnboundedReceiver<Command>) {
        let (sender, receiver) = mpsc::unbounded_channel();
        (Commands { brightness: sender.clone(), keyboard: sender.clone(), profiles: sender }, receiver)
    }

    pub fn send(&self, command: Command) -> Result<(), OpError> {
        let channel = match &command {
            Command::SetBrightness { .. } => &self.brightness,
            Command::SetKeyboardBrightness { .. } => &self.keyboard,
            _ => &self.profiles,
        };
        channel.send(command).map_err(|_| OpError::new(ErrorCode::Unavailable, "the backend has stopped"))
    }
}
