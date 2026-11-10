//! The state of the session as plain values: what the contract tells the clients.

use crate::manifest::Kind;
use crate::power::{Action, Capabilities};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Starting,
    Running,
    Ending,
    Sleeping,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EndAction {
    Logout,
    Reboot,
    PowerOff,
}

impl EndAction {
    pub fn of(action: Action) -> Option<EndAction> {
        match action {
            Action::PowerOff => Some(EndAction::PowerOff),
            Action::Reboot => Some(EndAction::Reboot),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Initiator {
    User,
    System,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Ending {
    pub action: EndAction,
    pub initiator: Initiator,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChildKind {
    Compositor,
    Shell,
    MaiaService,
    KdeService,
    Helper,
}

impl From<Kind> for ChildKind {
    fn from(kind: Kind) -> ChildKind {
        match kind {
            Kind::Shell => ChildKind::Shell,
            Kind::MaiaService => ChildKind::MaiaService,
            Kind::KdeService => ChildKind::KdeService,
            Kind::Helper => ChildKind::Helper,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChildState {
    Waiting,
    Running,
    Restarting,
    Failed,
    Stopped,
}

/// One child as the clients see it
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChildView {
    pub name: String,
    pub kind: ChildKind,
    pub state: ChildState,
    pub pid: u32,
    pub restarts: u32,
    pub last_exit: String,
}

impl ChildView {
    pub fn new(name: &str, kind: ChildKind) -> ChildView {
        ChildView { name: name.to_string(), kind, state: ChildState::Waiting, pid: 0, restarts: 0, last_exit: String::new() }
    }
}

/// What the clients see of the session
#[derive(Clone, Debug, PartialEq)]
pub struct View {
    pub state: State,
    pub ending: Option<Ending>,
    pub capabilities: Capabilities,
    pub children: Vec<ChildView>,
}

/// What the service tells about itself (SessionService.info)
#[derive(Clone, Debug, Default)]
pub struct Info {
    pub maia_version: String,
    pub compositor: String,
    pub session_id: String,
    pub backend: String,
}

/// What a client asks of the session (SessionControl)
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Request {
    Logout,
    Power(Action),
    RestartChild(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    None,
    NotAllowed,
    NotSupported,
    Busy,
    NotFound,
    Failed,
}

/// The answer to a Request (the contract's Result)
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outcome {
    pub error: ErrorCode,
    pub message: String,
}

impl Outcome {
    pub fn ok() -> Outcome {
        Outcome { error: ErrorCode::None, message: String::new() }
    }

    pub fn error(error: ErrorCode, message: impl Into<String>) -> Outcome {
        Outcome { error, message: message.into() }
    }
}
