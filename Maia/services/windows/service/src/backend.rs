//! What every compositor backend and the rest of the service exchange.
//!
//! A backend (today `kwin`) runs as one task: it sends `BackendEvent`s about the windows and
//! executes the `Command`s it receives. Both directions are channels, so the RPC side never waits
//! for the compositor, and tests drive the service with a fake backend (see tests/service.rs).

use tokio::sync::oneshot;

use crate::model::Window;

/// What the backend tells the rest of the service
#[derive(Debug)]
pub enum BackendEvent {
    /// A window appeared or changed: its whole current state
    Window(Window),
    Removed(String),
}

/// What the rest of the service asks the backend to do
#[derive(Debug)]
pub enum Command {
    /// Sets the bits `flags` of the window state to the values in `state` (contract state* bits)
    SetState { id: String, flags: u32, state: u32 },
    Close(String),
    RequestMove(String),
    RequestResize(String),
    /// The bitmap icon of the window (a QIcon serialized with QDataStream); dropping `reply` means
    /// there is none
    FetchIcon { id: String, reply: oneshot::Sender<Vec<u8>> },
}

/// What a backend is and can do, for WindowService.info()
#[derive(Clone, Debug)]
pub struct BackendInfo {
    pub name: String,
    /// Contract cap* bits
    pub capabilities: u32,
}
