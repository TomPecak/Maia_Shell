//! maia-windows: the window service of a Maia session.
//!
//! Started by the session script after the compositor; ends with the compositor connection, on
//! SIGTERM or Ctrl+C. One instance per compositor: the socket name contains $WAYLAND_DISPLAY, so a
//! nested session gets its own service.
//!
//! Socket: $MAIA_WINDOWS_SOCKET, or $XDG_RUNTIME_DIR/maia/windows-$WAYLAND_DISPLAY.sock

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::PathBuf;

use maia_windows::apps::AppIndex;
use maia_windows::kwin;
use maia_windows::rpc::{Hub, WindowService};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;

fn socket_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_WINDOWS_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    let display = display.rsplit('/').next().unwrap_or("wayland-0").to_string();
    runtime.join("maia").join(format!("windows-{display}.sock"))
}

/// Takes over the socket path, unless another service still answers there
fn bind(path: &PathBuf) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("another maia-windows already serves {}", path.display()),
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
            eprintln!("maia-windows: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let path = socket_path();
    let listener = bind(&path)?;
    // At the end the socket is removed only if it is still ours (not of a newer instance)
    let socket_inode = std::fs::metadata(&path)?.ino();

    let local = tokio::task::LocalSet::new();
    let result = local
        .run_until(async {
            let (event_sender, events) = mpsc::unbounded_channel();
            let (command_sender, commands) = mpsc::unbounded_channel();
            let hub = Hub::new(AppIndex::from_environment());
            let service = WindowService::client(hub.clone(), command_sender, kwin::info());
            tokio::task::spawn_local(Hub::run(hub, events));

            eprintln!("maia-windows {} serves {}", env!("CARGO_PKG_VERSION"), path.display());
            let accept = async {
                loop {
                    match listener.accept().await {
                        Ok((stream, _)) => maia_windows::rpc::serve(stream, service.clone()),
                        Err(error) => eprintln!("maia-windows: accept: {error}"),
                    }
                }
            };

            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                result = kwin::run(event_sender, commands) => result,
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
