//! maia-power-service: the power service of a Maia session.
//!
//! Started by the session service (session.toml); ends on SIGTERM or Ctrl+C. One instance per
//! session: the socket name contains $WAYLAND_DISPLAY, so a nested development session gets its own.
//!
//! Socket: $MAIA_POWER_SOCKET, or $XDG_RUNTIME_DIR/maia/power-$WAYLAND_DISPLAY.sock
//! Backend: $MAIA_POWER_BACKEND = "system" (default) or "fake" (a simulated laptop: nothing reaches
//! the machine)

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::PathBuf;

use maia_power::backend::Commands;
use maia_power::rpc::{Hub, PowerService};
use maia_power::{fake, system};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;

fn socket_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_POWER_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    let display = display.rsplit('/').next().unwrap_or("wayland-0").to_string();
    runtime.join("maia").join(format!("power-{display}.sock"))
}

/// Takes over the socket path, unless another service still answers there
fn bind(path: &PathBuf) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("another maia-power-service already serves {}", path.display()),
        ));
    }
    let _ = std::fs::remove_file(path);
    tokio::net::UnixListener::bind(path)
}

fn main() -> std::process::ExitCode {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build();
    match runtime.map_err(Into::into).and_then(|runtime| runtime.block_on(run())) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("maia-power-service: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let backend = std::env::var("MAIA_POWER_BACKEND").unwrap_or_else(|_| system::NAME.into());
    if backend != system::NAME && backend != fake::NAME {
        return Err(format!("unknown backend \"{backend}\" ({} or {})", system::NAME, fake::NAME).into());
    }
    let path = socket_path();
    let listener = bind(&path)?;
    // At the end the socket is removed only if it is still ours (not of a newer instance)
    let socket_inode = std::fs::metadata(&path)?.ino();

    let local = tokio::task::LocalSet::new();
    let result = local
        .run_until(async {
            let (event_sender, events) = mpsc::unbounded_channel();
            let hub = Hub::new();
            tokio::task::spawn_local(Hub::run(hub.clone(), events));
            let (commands, backend_task): (Commands, std::pin::Pin<Box<dyn std::future::Future<Output = ()>>>) =
                if backend == fake::NAME {
                    let (commands, receiver) = Commands::single();
                    // No test drives it: the battery lives by itself
                    let (_actions, actions) = mpsc::unbounded_channel();
                    (commands, Box::pin(fake::run(event_sender, receiver, actions, fake::Timing::realistic())))
                } else {
                    let (commands, receivers) = system::channels();
                    (commands, Box::pin(system::run(event_sender, receivers)))
                };
            let service = PowerService::client(hub, commands, &backend);

            eprintln!("maia-power-service {} ({backend}) serves {}", env!("CARGO_PKG_VERSION"), path.display());
            let accept = async {
                loop {
                    match listener.accept().await {
                        Ok((stream, _)) => maia_power::rpc::serve(stream, service.clone()),
                        Err(error) => eprintln!("maia-power-service: accept: {error}"),
                    }
                }
            };
            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                _ = backend_task => Ok::<(), Box<dyn std::error::Error>>(()),
                _ = accept => Ok(()),
                _ = tokio::signal::ctrl_c() => Ok(()),
                _ = terminate.recv() => Ok(()),
            }
        })
        .await;

    if std::fs::metadata(&path).map(|m| m.ino()).ok() == Some(socket_inode) {
        let _ = std::fs::remove_file(&path);
    }
    result
}
