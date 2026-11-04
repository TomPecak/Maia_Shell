//! maia-network-service: the network service of a Maia session.
//!
//! Started by the session script; ends on SIGTERM or Ctrl+C. One instance per session: the socket
//! name contains $WAYLAND_DISPLAY, so a nested development session gets its own service.
//!
//! Socket: $MAIA_NETWORK_SOCKET, or $XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock
//! Backend: $MAIA_NETWORK_BACKEND = "networkmanager" (default) or "fake" (simulated, for tests and
//! interface work: nothing reaches the real network)

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::PathBuf;

use maia_network::fake;
use maia_network::prompt::Prompter;
use maia_network::rpc::{Hub, NetworkService};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;

fn socket_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_NETWORK_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    let display = display.rsplit('/').next().unwrap_or("wayland-0").to_string();
    runtime.join("maia").join(format!("network-{display}.sock"))
}

/// Takes over the socket path, unless another service still answers there
fn bind(path: &PathBuf) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("another maia-network-service already serves {}", path.display()),
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
            eprintln!("maia-network-service: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let backend = std::env::var("MAIA_NETWORK_BACKEND").unwrap_or_else(|_| "networkmanager".into());
    let path = socket_path();
    let listener = bind(&path)?;
    // At the end the socket is removed only if it is still ours (not of a newer instance)
    let socket_inode = std::fs::metadata(&path)?.ino();

    let local = tokio::task::LocalSet::new();
    let result = local
        .run_until(async {
            let (event_sender, events) = mpsc::unbounded_channel();
            let (command_sender, commands) = mpsc::unbounded_channel();
            let (prompter, prompts) = Prompter::new();
            let hub = Hub::new();
            let service = NetworkService::client(hub.clone(), command_sender, &backend);
            tokio::task::spawn_local(Hub::run(hub.clone(), events));
            tokio::task::spawn_local(Hub::run_prompts(hub, prompts));

            eprintln!("maia-network-service {} ({backend}) serves {}", env!("CARGO_PKG_VERSION"), path.display());
            let accept = async {
                loop {
                    match listener.accept().await {
                        Ok((stream, _)) => maia_network::rpc::serve(stream, service.clone()),
                        Err(error) => eprintln!("maia-network-service: accept: {error}"),
                    }
                }
            };
            let backend_task = async {
                match backend.as_str() {
                    fake::NAME => {
                        fake::run(event_sender, commands, prompter, fake::Timing::realistic()).await;
                        Ok(())
                    }
                    other => Err(format!("unknown backend \"{other}\" (networkmanager or fake)").into()),
                }
            };

            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                result = backend_task => result,
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
