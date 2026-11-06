//! maia-appearance-service: the appearance service of a Maia session.
//!
//! Started by the session script; ends on SIGTERM or Ctrl+C. One instance per session: the socket
//! name contains $WAYLAND_DISPLAY, so a nested development session gets its own service.
//!
//! Socket: $MAIA_APPEARANCE_SOCKET, or $XDG_RUNTIME_DIR/maia/appearance-$WAYLAND_DISPLAY.sock
//! Backend: $MAIA_APPEARANCE_BACKEND = "kwin" (default) or "fake" (in memory, for tests and
//! interface work: no compositor setting is touched)

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::PathBuf;

use maia_appearance::compositor;
use maia_appearance::decorations::Decorations;
use maia_appearance::paths::Paths;
use maia_appearance::rpc::{self, AppearanceService};
use tokio::signal::unix::{SignalKind, signal};

const NAME: &str = "maia-appearance-service";

fn socket_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_APPEARANCE_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    let display = display.rsplit('/').next().unwrap_or("wayland-0").to_string();
    runtime.join("maia").join(format!("appearance-{display}.sock"))
}

/// Takes over the socket path, unless another service still answers there
fn bind(path: &PathBuf) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(std::io::ErrorKind::AddrInUse, format!("another {NAME} already serves {}", path.display())));
    }
    let _ = std::fs::remove_file(path);
    tokio::net::UnixListener::bind(path)
}

fn main() -> std::process::ExitCode {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build();
    match runtime.map_err(Into::into).and_then(|runtime| runtime.block_on(run())) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{NAME}: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let backend = std::env::var("MAIA_APPEARANCE_BACKEND").unwrap_or_else(|_| compositor::kwin::NAME.into());
    let paths = Paths::from_environment();
    let compositor = compositor::create(&backend, &paths)?;
    let path = socket_path();
    let listener = bind(&path)?;
    // At the end the socket is removed only if it is still ours (not of a newer instance)
    let socket_inode = std::fs::metadata(&path)?.ino();

    let local = tokio::task::LocalSet::new();
    let result: Result<(), Box<dyn std::error::Error>> = local
        .run_until(async {
            let decorations = Decorations::start(paths, compositor).await;
            let service = AppearanceService::client(&backend, decorations);
            eprintln!("{NAME} {} ({backend}) serves {}", env!("CARGO_PKG_VERSION"), path.display());
            let accept = async {
                loop {
                    match listener.accept().await {
                        Ok((stream, _)) => rpc::serve(stream, service.clone()),
                        Err(error) => eprintln!("{NAME}: accept: {error}"),
                    }
                }
            };
            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                _ = accept => {}
                _ = tokio::signal::ctrl_c() => {}
                _ = terminate.recv() => {}
            }
            Ok(())
        })
        .await;

    if std::fs::metadata(&path).map(|m| m.ino()).ok() == Some(socket_inode) {
        let _ = std::fs::remove_file(&path);
    }
    result
}
