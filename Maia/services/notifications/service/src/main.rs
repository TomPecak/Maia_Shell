//! maia-notifications-service: the notification server of a Maia session.
//!
//! Started by the session service (session.toml), early: applications may send notifications as
//! soon as they start. Ends on SIGTERM or Ctrl+C. One instance per session: the names of its
//! sockets and its image directory contain $WAYLAND_DISPLAY, so a nested development session (with
//! its own D-Bus session bus) gets its own.
//!
//! Sockets: $MAIA_NOTIFICATIONS_SOCKET or $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock
//!          (Notifier), $MAIA_NOTIFICATIONS_CENTER_SOCKET or
//!          $XDG_RUNTIME_DIR/maia/notifications-center-$WAYLAND_DISPLAY.sock (NotificationCenter)
//! Images:  $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY/
//! D-Bus:   org.freedesktop.Notifications on the session bus; MAIA_NOTIFICATIONS_DBUS=0 leaves it out.
//!          org.kde.JobViewServer and org.kde.kuiserver (jobs); MAIA_NOTIFICATIONS_JOBS=0 leaves
//!          them out (KIO then shows its own progress dialog)

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};

use maia_notifications::hub::Hub;
use maia_notifications::rpc::{Center, NotifierImpl};
use maia_notifications::{dbus, image, rpc};
use tokio::signal::unix::{SignalKind, signal};

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir).join("maia")
}

/// The name of the session's display (WAYLAND_DISPLAY may be an absolute path)
fn display() -> String {
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    display.rsplit('/').next().unwrap_or("wayland-0").to_string()
}

fn socket_path(variable: &str, name: &str) -> PathBuf {
    match std::env::var_os(variable) {
        Some(path) => PathBuf::from(path),
        None => runtime_dir().join(format!("{name}-{}.sock", display())),
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
            format!("another maia-notifications-service already serves {}", path.display()),
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
            eprintln!("maia-notifications-service: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn accept(listener: tokio::net::UnixListener, bootstrap: capnp::capability::Client) {
    loop {
        match listener.accept().await {
            Ok((stream, _)) => rpc::serve(stream, bootstrap.clone()),
            Err(error) => eprintln!("maia-notifications-service: accept: {error}"),
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let notifier_path = socket_path("MAIA_NOTIFICATIONS_SOCKET", "notifications");
    let center_path = socket_path("MAIA_NOTIFICATIONS_CENTER_SOCKET", "notifications-center");
    let notifier_listener = bind(&notifier_path)?;
    let center_listener = bind(&center_path)?;
    // At the end the sockets are removed only if they are still ours (not of a newer instance)
    let inodes = [std::fs::metadata(&notifier_path)?.ino(), std::fs::metadata(&center_path)?.ino()];

    let image_dir = runtime_dir().join(format!("notifications-{}", display()));
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&image_dir)?;
    image::clean_directory(&image_dir);

    let local = tokio::task::LocalSet::new();
    let result = local
        .run_until(async {
            let hub = Hub::new(Some(image_dir.clone()));

            // D-Bus: without it Maia's programs are still served
            let _connection = if std::env::var("MAIA_NOTIFICATIONS_DBUS").as_deref() == Ok("0") {
                None
            } else {
                match zbus::Connection::session().await {
                    Ok(connection) => {
                        dbus::serve(&connection, &hub).await?;
                        if !dbus::take_name(&connection).await? {
                            eprintln!("maia-notifications-service: another notification server keeps {}", dbus::NAME);
                        }
                        // The job server: KIO (Dolphin) then reports its progress here instead of in
                        // its own dialog; MAIA_NOTIFICATIONS_JOBS=0 leaves it to the dialog
                        if std::env::var("MAIA_NOTIFICATIONS_JOBS").as_deref() != Ok("0")
                            && !dbus::take_job_names(&connection).await?
                        {
                            eprintln!("maia-notifications-service: another job server keeps org.kde.JobViewServer");
                        }
                        Some(connection)
                    }
                    Err(error) => {
                        eprintln!("maia-notifications-service: no D-Bus session bus: {error}");
                        None
                    }
                }
            };

            eprintln!(
                "maia-notifications-service {} serves {} and {}",
                env!("CARGO_PKG_VERSION"),
                notifier_path.display(),
                center_path.display()
            );
            let notifier = NotifierImpl::client(hub.clone());
            let center = Center::client(hub.clone());
            let mut terminate = signal(SignalKind::terminate())?;
            tokio::select! {
                _ = accept(notifier_listener, notifier.client) => {}
                _ = accept(center_listener, center.client) => {}
                _ = tokio::signal::ctrl_c() => {}
                _ = terminate.recv() => {}
            }
            Ok::<(), Box<dyn std::error::Error>>(())
        })
        .await;

    for (path, inode) in [&notifier_path, &center_path].into_iter().zip(inodes) {
        if std::fs::metadata(path).map(|m| m.ino()).ok() == Some(inode) {
            let _ = std::fs::remove_file(path);
        }
    }
    image::clean_directory(&image_dir);
    let _ = std::fs::remove_dir(&image_dir);
    result
}
