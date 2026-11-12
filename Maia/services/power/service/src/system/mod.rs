//! The system's services as the backend: three independent sources, each a task of its own.
//!
//! ```text
//!   UPower ─────────────► upower.rs    batteries, charger, lid, keyboard backlight
//!   /sys/class/backlight ► backlight.rs brightness (written through logind)
//!   power-profiles-daemon ► profiles.rs  the power profile and its holds
//! ```
//!
//! A source that is missing (no UPower on a minimal system, no power-profiles-daemon) says so in its
//! part of the state; the others go on. Without a system bus at all only the brightness can be read
//! (and written directly, where the user may).

pub mod backlight;
pub mod dbus;
pub mod profiles;
pub mod upower;

use tokio::sync::mpsc;

use crate::backend::{BackendEvent, Command, Commands};

pub const NAME: &str = "system";

/// The command channels of the three sources
pub struct Receivers {
    pub brightness: mpsc::UnboundedReceiver<Command>,
    pub keyboard: mpsc::UnboundedReceiver<Command>,
    pub profiles: mpsc::UnboundedReceiver<Command>,
}

pub fn channels() -> (Commands, Receivers) {
    let (brightness, brightness_rx) = mpsc::unbounded_channel();
    let (keyboard, keyboard_rx) = mpsc::unbounded_channel();
    let (profiles, profiles_rx) = mpsc::unbounded_channel();
    (
        Commands { brightness, keyboard, profiles },
        Receivers { brightness: brightness_rx, keyboard: keyboard_rx, profiles: profiles_rx },
    )
}

/// Runs the three sources on the system bus and the real sysfs until all have ended
pub async fn run(events: mpsc::UnboundedSender<BackendEvent>, receivers: Receivers) {
    let conn = match zbus::Connection::system().await {
        Ok(conn) => Some(conn),
        Err(error) => {
            eprintln!("maia-power-service: no system D-Bus ({error}): batteries and profiles unavailable");
            None
        }
    };
    run_with(conn, backlight::sysfs_root(), events, receivers).await;
}

/// The sources on a given bus and sysfs root (the tests give a private bus and a directory)
pub async fn run_with(
    conn: Option<zbus::Connection>,
    sysfs: std::path::PathBuf,
    events: mpsc::UnboundedSender<BackendEvent>,
    receivers: Receivers,
) {
    let backlight = backlight::run(conn.clone(), sysfs, events.clone(), receivers.brightness);
    match conn {
        Some(conn) => {
            let upower = upower::run(conn.clone(), events.clone(), receivers.keyboard);
            let profiles = profiles::run(conn, events, receivers.profiles);
            tokio::join!(backlight, upower, profiles);
        }
        None => {
            let _ = events.send(BackendEvent::Status(crate::model::PowerStatus::unavailable()));
            let _ = events.send(BackendEvent::Keyboard(crate::model::KeyboardBacklight::unavailable()));
            let _ = events.send(BackendEvent::Profiles(crate::model::Profiles::unavailable()));
            // Commands of the missing sources: answered as unavailable
            let refuse = |mut rx: mpsc::UnboundedReceiver<Command>| async move {
                while let Some(command) = rx.recv().await {
                    refuse_unavailable(command);
                }
            };
            tokio::join!(backlight, refuse(receivers.keyboard), refuse(receivers.profiles));
        }
    }
}

fn refuse_unavailable(command: Command) {
    use crate::backend::{ErrorCode, OpError};
    let error = || OpError::new(ErrorCode::Unavailable, "no system D-Bus");
    match command {
        Command::SetBrightness { reply, .. } | Command::SetKeyboardBrightness { reply, .. } | Command::SetProfile { reply, .. } => {
            let _ = reply.send(Err(error()));
        }
        Command::HoldProfile { reply, .. } => {
            let _ = reply.send(Err(error()));
        }
        Command::ReleaseProfile { .. } => {}
    }
}
