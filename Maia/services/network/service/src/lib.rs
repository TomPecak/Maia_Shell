//! Maia network service (maia-network-service).
//!
//! The only process of a Maia session that talks to NetworkManager. It serves the state of Wi-Fi to
//! shells, Maia Settings and apps over Cap'n Proto (../contract/network.capnp) and carries out what
//! they ask for. What the user interface offers is described in ../docs/gnome-wifi-features.md.
//!
//! ```text
//!   NetworkManager ──► backend (nm.rs) ──► hub (rpc.rs) ──────────► clients (Maia.Network)
//!   (D-Bus, zbus)      plain values         networks from APs,      snapshot, then changes;
//!                ◄──── Command ─────────── control ◄─────────────── control
//!   secret agent ────► Prompter (prompt.rs) ──► the shell's SecretPrompter (password dialog)
//! ```
//!
//! - `model`: the state as plain values, and how access points become networks.
//! - `settings`: connection settings and secrets, password requests and their checks.
//! - `backend`: the events and commands between a backend and the hub.
//! - `nm`, `nmdefs`, `nmsettings`: the NetworkManager backend, NetworkManager's numbers, and its
//!   profiles as dictionaries.
//! - `agent`: the secret agent NetworkManager asks for passwords.
//! - `fake`: a simulated NetworkManager for tests and for interface work (MAIA_NETWORK_BACKEND=fake).
//! - `rpc`: the Cap'n Proto side: state to every listener, control, the password prompter.
//! - `prompt`: how a backend asks the user for secrets.
//! - `throttle`: at most one change per object every 250 ms goes out.
//! - `qr`: the QR code of a network for sharing.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! work per event is microseconds. Nothing blocks: D-Bus and the clients are awaited, never waited
//! for.

pub mod network_capnp {
    include!(concat!(env!("OUT_DIR"), "/network_capnp.rs"));
}

pub mod agent;
pub mod backend;
pub mod fake;
pub mod model;
pub mod nm;
pub mod nmdefs;
pub mod nmsettings;
pub mod prompt;
pub mod qr;
pub mod rpc;
pub mod settings;
pub mod throttle;
