//! Maia power service (maia-power-service).
//!
//! The only process of a Maia session that reads and changes the power state: batteries (the
//! computer's and devices'), the brightness of the screen and of the keyboard, the power profile.
//! It uses the system's own services, nothing of a desktop environment, and serves the shells, Maia
//! Settings and apps over Cap'n Proto (../contract/power.capnp) through the Maia.Power QML module.
//!
//! ```text
//!   UPower, sysfs + logind,      backend: system/        hub (rpc.rs)          clients (Maia.Power)
//!   power-profiles-daemon  ────► or fake.rs  ──events──► state, events.rs ───► snapshot, then changes
//!                          ◄──── Command ◄────────────── control (checked) ◄── setBrightness, setProfile, …
//! ```
//!
//! - `model`: the state as plain values; UPower's numbers, the brightness arithmetic, battery icons.
//! - `backend`: the events and commands between a backend and the hub.
//! - `system`: the real backend (UPower, the backlight through sysfs and logind, power-profiles-daemon).
//! - `fake`: a simulated laptop for tests and interface work (MAIA_POWER_BACKEND=fake).
//! - `events`: notifications (charger, low battery) from two states one after the other.
//! - `rpc`: the Cap'n Proto side; `throttle`: at most one change per object every 50 ms.
//!
//! Everything runs in one thread (tokio current_thread): Cap'n Proto objects are not Send, and the
//! work per event is microseconds. Nothing blocks: D-Bus and the clients are awaited, never waited for.

pub mod power_capnp {
    include!(concat!(env!("OUT_DIR"), "/power_capnp.rs"));
}

pub mod backend;
pub mod events;
pub mod fake;
pub mod model;
pub mod rpc;
pub mod system;
pub mod throttle;
