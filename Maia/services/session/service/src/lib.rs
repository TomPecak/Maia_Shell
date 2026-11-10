//! Maia session service (maia-session-service).
//!
//! The main process of a Maia session: the session script (phase 1) ends with `exec` into it. It
//! starts the compositor, waits until the compositor reports its display, starts KDE's and Maia's
//! services and the shell (appMaiaServer), starts them again after a crash, ends the session in
//! order, and is the only part of Maia that talks to systemd-logind. Shells and apps reach it over
//! Cap'n Proto (../contract/session.capnp) through the Maia.Session QML module.
//!
//! ```text
//!   SDDM ──► run_maia_kwin.sh (environment) ──exec──► maia-session-service
//!                                                       ├─ compositor ──► ready helper (--compositor-ready)
//!                                                       ├─ kglobalacceld, KDE units
//!                                                       ├─ maia-*-service
//!                                                       └─ appMaiaServer
//! ```
//!
//! - `manifest`, `expand`: session.toml, what the session runs.
//! - `session`: the event loop; the start, the children, the end.
//! - `policy`: when a child that ended is started again.
//! - `procs`: starting, reaping and ending processes (process groups, PDEATHSIG, subreaper).
//! - `power`: systemd-logind, and a fake of it for tests and nested sessions.
//! - `rpc`, `model`: the Cap'n Proto side and the state it shows.
//! - `ready`: the ready helper the compositor runs.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! children must be started by the thread that stays (PR_SET_PDEATHSIG belongs to a thread).

pub mod session_capnp {
    include!(concat!(env!("OUT_DIR"), "/session_capnp.rs"));
}

pub mod expand;
pub mod manifest;
pub mod model;
pub mod policy;
pub mod power;
pub mod procs;
pub mod ready;
pub mod rpc;
pub mod session;
