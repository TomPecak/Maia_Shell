//! Maia appearance service (maia-appearance-service).
//!
//! The one process of a Maia session that knows how the compositor stores its look. Shells, Maia
//! Settings and apps use the contract (../contract/*.capnp, through the Maia.Appearance QML module)
//! and never touch kwinrc or the compositor's D-Bus themselves.
//!
//! ```text
//!   clients ──Cap'n Proto──► rpc/ ──► decorations/ (the area: catalog, choice, install) ──► compositor/
//!   (Maia.Appearance)         │        no Cap'n Proto here, plain values and async fns       kwin.rs: kwinrc,
//!                             └─ events ◄── decorations/ (themes or choice changed)          D-Bus; fake.rs
//! ```
//!
//! Where things are (each module says more in its own documentation):
//!
//! - `compositor/`: one backend per compositor behind the `Compositor` trait. `kwin.rs` writes
//!   kwinrc (with kwriteconfig6), tells KWin (D-Bus reloadConfig) and checks what KWin took
//!   (supportInformation). `fake.rs` for tests. Wayfire comes here as `wayfire.rs`.
//! - `decorations/`: the window decorations area. `theme.rs` the values (ids "engine:name"),
//!   `catalog.rs` finds themes on disk, `qtplugin.rs` reads names of native plugins, `install.rs`
//!   installs and removes user themes, `frontends.rs` remembers a choice per frontend, `mod.rs`
//!   puts it together (one change at a time, events to listeners).
//! - `rpc/`: the Cap'n Proto side: `mod.rs` the service and serve(), `decorations.rs` the
//!   Decorations interface, its listeners and the conversions.
//! - Shared: `error.rs` (ErrorCode, OpError), `paths.rs` (XDG and plugin directories, where a file
//!   comes from), `kconfig.rs` (reading KConfig/desktop files), `inotify.rs` (watching directories).
//!
//! A new area (icons, cursors, colors) is a new directory next to `decorations/`, a new
//! `rpc/<area>.rs`, a new `contract/<area>.capnp` and a method in AppearanceService; see
//! ../docs/adding-an-area.md.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send. Nothing
//! blocks it: files go through tokio::fs or spawn_blocking (directory scans), programs through
//! tokio::process, D-Bus through zbus.

pub mod common_capnp {
    include!(concat!(env!("OUT_DIR"), "/common_capnp.rs"));
}
pub mod decorations_capnp {
    include!(concat!(env!("OUT_DIR"), "/decorations_capnp.rs"));
}
pub mod appearance_capnp {
    include!(concat!(env!("OUT_DIR"), "/appearance_capnp.rs"));
}

pub mod compositor;
pub mod decorations;
pub mod error;
pub mod inotify;
pub mod kconfig;
pub mod paths;
pub mod rpc;
#[doc(hidden)]
pub mod test_support;
