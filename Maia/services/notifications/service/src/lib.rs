//! Maia notification service (maia-notifications-service).
//!
//! The notification server of a Maia session: it keeps the list of notifications for the session,
//! whoever sent them and whichever shell shows them. A shell that restarts or is switched finds the
//! list as it was.
//!
//! ```text
//!   applications ──D-Bus org.freedesktop.Notifications──┐   (dbus.rs, + KDE's extensions)
//!   Maia's programs ──Cap'n Proto Notifier─────────────┼──► hub (hub.rs, model.rs) ──Cap'n Proto──► shells
//!                                                      │      list, rules, batches     NotificationCenter
//!   senders ◄── ActionInvoked, Replied, Closed ────────┘      (one per frame)
//! ```
//!
//! - `model`: the notifications and the rules of the list (ids, replacing, limits, do not disturb);
//! - `markup`: the body made safe; `image`: images as file:// URLs, pixels as PNG;
//! - `hub`: the shared state, batches to the shells, events to the senders;
//! - `dbus`: org.freedesktop.Notifications; `rpc`: NotificationCenter and Notifier.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! work per notification is microseconds. Nothing blocks: a Notify call answers at once; images are
//! written on tokio's blocking threads; shells get one batch per frame at most.

pub mod notifications_capnp {
    include!(concat!(env!("OUT_DIR"), "/notifications_capnp.rs"));
}

pub mod dbus;
pub mod hub;
pub mod image;
pub mod markup;
pub mod model;
pub mod rpc;

/// What the server can do (GetCapabilities, NotificationCenter.info): only what Maia's shells show.
/// Not yet: "sound" (no shell plays sounds), "body-images", "action-icons", "x-kde-urls".
pub const CAPABILITIES: [&str; 10] = [
    "actions",
    "body",
    "body-hyperlinks",
    "body-markup",
    "icon-static",
    "persistence",
    "inline-reply",
    "inhibitions",
    "x-kde-origin-name",
    "x-kde-display-appname",
];
