//! Maia tray service (maia-tray-service).
//!
//! The system tray of a Maia session: the StatusNotifierWatcher applications register their icons
//! with, and the only host that reads them, for whichever shell shows them. A shell that restarts
//! or is switched finds the icons as they were.
//!
//! ```text
//!   applications ──D-Bus StatusNotifierItem, dbusmenu──► items (sni.rs), menus (menu.rs)
//!        │                                                     │
//!        └──RegisterStatusNotifierItem──► watcher (watcher.rs) ┴──► hub (hub.rs) ──Cap'n Proto──► shells
//!                                                                  batches, one per frame    TrayHost
//!   X11 icons ──XEmbed──► xembedsniproxy (KDE) ──► an item like any other
//! ```
//!
//! - `model`: items and how their D-Bus properties are read; `markup`: their texts as plain text;
//! - `image`: icons as theme names and file:// URLs, pixels as PNG files shared by content;
//! - `desktop`: which application an item belongs to;
//! - `hub`: the shared state, batches to the shells; `sni`: one task per item;
//! - `watcher`: org.kde.StatusNotifierWatcher; `menu`: com.canonical.dbusmenu; `rpc`: TrayHost.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! work per change is microseconds. Nothing waits for an application: each item and each open menu
//! has its own task with time limits on its calls; images are written on blocking threads.

pub mod tray_capnp {
    include!(concat!(env!("OUT_DIR"), "/tray_capnp.rs"));
}

pub mod desktop;
pub mod hub;
pub mod image;
pub mod markup;
pub mod menu;
pub mod model;
pub mod rpc;
pub mod sni;
pub mod watcher;
