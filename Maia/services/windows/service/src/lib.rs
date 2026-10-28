//! Maia window service.
//!
//! The service is the only Maia process that talks to the compositor about the windows of other
//! applications, and it serves the window list to shells and apps over Cap'n Proto
//! (../contract/windows.capnp). Data flows in one direction through four parts:
//!
//! ```text
//!   compositor ──► backend (kwin.rs) ──► store (model.rs) ──► RPC (rpc.rs) ──► clients
//!                  protocol events        + app identity       snapshot, then
//!                  ◄── Command ───────────── (apps.rs) ◄─────── changes; control
//! ```
//!
//! - `backend`: the events and commands a compositor backend exchanges with the service.
//! - `kwin`: speaks org_kde_plasma_window_management with KWin, turns its events into whole
//!   `Window` values and executes `Command`s. Knows nothing about Cap'n Proto.
//! - `model`: the window list (pure logic, no I/O): which windows exist, in which order, and what
//!   changed. Adds what the compositor does not know (last activation time).
//! - `apps`: which application a window belongs to (desktop entries), like TaskTools in KDE.
//! - `rpc`: the Cap'n Proto side: snapshot + changes to every listener, control, icons.
//! - `throttle`: at most one change per window and frame goes out (a dragged window changes its
//!   geometry on every frame).
//! - `launch`: starting applications from their desktop entries.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! work per event is microseconds. Nothing blocks: the Wayland socket is polled with tokio.

pub mod windows_capnp {
    include!(concat!(env!("OUT_DIR"), "/windows_capnp.rs"));
}

pub mod apps;
pub mod backend;
pub mod kwin;
pub mod launch;
pub mod model;
pub mod rpc;
pub mod throttle;
