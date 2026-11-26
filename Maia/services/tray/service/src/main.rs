//! maia-tray-service: the system tray of a Maia session.
//!
//! Started by the session service (session.toml), early: applications show their icons as soon as
//! they start, and the ones that started before register when the watcher appears. Ends on SIGTERM
//! or Ctrl+C. One instance per session: the name of its socket and its image directory contain
//! $WAYLAND_DISPLAY, so a nested development session (with its own D-Bus session bus) gets its own.
//!
//! Socket: $MAIA_TRAY_SOCKET or $XDG_RUNTIME_DIR/maia/tray-$WAYLAND_DISPLAY.sock (TrayHost)
//! Images: $XDG_RUNTIME_DIR/maia/tray-$WAYLAND_DISPLAY/
//! D-Bus:  org.kde.StatusNotifierWatcher (or a host of the program that keeps it) and
//!         org.kde.StatusNotifierHost-<pid> on the session bus

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};

use maia_tray::hub::Hub;
use maia_tray::image::{self, ImageStore};
use maia_tray::rpc::{self, Host};
use maia_tray::{desktop, watcher};
use tokio::signal::unix::{SignalKind, signal};

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir).join("maia")
}

/// The name of the session's display (WAYLAND_DISPLAY may be an absolute path)
fn display() -> String {
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    display.rsplit('/').next().unwrap_or("wayland-0").to_string()
}

fn socket_path() -> PathBuf {
    match std::env::var_os("MAIA_TRAY_SOCKET") {
        Some(path) => PathBuf::from(path),
        None => runtime_dir().join(format!("tray-{}.sock", display())),
    }
}

/// Takes over the socket path, unless another service still answers there
fn bind(path: &Path) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("another maia-tray-service already serves {}", path.display()),
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
            eprintln!("maia-tray-service: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn accept(listener: tokio::net::UnixListener, bootstrap: capnp::capability::Client) {
    loop {
        match listener.accept().await {
            Ok((stream, _)) => rpc::serve(stream, bootstrap.clone()),
            Err(error) => eprintln!("maia-tray-service: accept: {error}"),
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let path = socket_path();
    let listener = bind(&path)?;
    // At the end the socket is removed only if it is still ours (not of a newer instance)
    let inode = std::fs::metadata(&path)?.ino();

    let image_dir = runtime_dir().join(format!("tray-{}", display()));
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&image_dir)?;
    image::clean_directory(&image_dir);

    let local = tokio::task::LocalSet::new();
    let result = local
        .run_until(async {
            // Without the session bus there are no items to show
            let connection = zbus::Connection::session().await?;
            let hub = Hub::new(ImageStore::new(Some(image_dir.clone())), Some(connection.clone()));

            // The applications' names and icons, read in the background; items found meanwhile get
            // theirs when they are read
            let weak = std::rc::Rc::downgrade(&hub);
            tokio::task::spawn_local(async move {
                let read = tokio::task::spawn_blocking(|| desktop::read_apps(&desktop::data_dirs(), &desktop::languages()));
                if let (Ok(apps), Some(hub)) = (read.await, weak.upgrade()) {
                    Hub::set_apps(&hub, apps);
                }
            });

            let ours = watcher::serve(&connection, &hub).await?;
            eprintln!(
                "maia-tray-service {} serves {}{}",
                env!("CARGO_PKG_VERSION"),
                path.display(),
                if ours { ", the watcher" } else { ", a host of another watcher" }
            );
            let host = Host::client(hub.clone());
            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                _ = accept(listener, host.client) => {}
                _ = tokio::signal::ctrl_c() => {}
                _ = terminate.recv() => {}
            }
            Ok::<(), Box<dyn std::error::Error>>(())
        })
        .await;

    if std::fs::metadata(&path).map(|m| m.ino()).ok() == Some(inode) {
        let _ = std::fs::remove_file(&path);
    }
    image::clean_directory(&image_dir);
    let _ = std::fs::remove_dir(&image_dir);
    result
}
