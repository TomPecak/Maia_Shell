//! maia-session-service: the main process of a Maia session.
//!
//!   maia-session-service --compositor <name> [--without <process>]...
//!       runs a session (the session script's phase 1 ends with exec into this)
//!   maia-session-service --compositor-ready
//!       the ready helper: run by the compositor, reports its display to the service; also
//!       without arguments when MAIA_SESSION_HELPER=compositor-ready (Wayfire's [autostart]
//!       runs "$MAIA_SESSION_SCRIPT", quoted, so it must be a single program)
//!
//! Environment:
//!   MAIA_SESSION_MANIFEST  session.toml to read; default <prefix>/etc/maia/session.toml, where
//!                          <prefix> is the directory above the one of this program (libexec)
//!   MAIA_SESSION_SOCKET    the socket; default $XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock
//!   MAIA_SESSION_BACKEND   "logind" (default) or "fake" (nothing reaches the machine)
//!   MAIA_SESSION_TEST=1    a test next to a real session: no systemd --user units, no
//!                          export of the environment to systemd
//!   MAIA_PREFIX, MAIA_VERSION, MAIA_CONFIG_DIR   for session.toml; derived when unset

use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};

use maia_session::manifest::Manifest;
use maia_session::model::Info;
use maia_session::procs::{self, Environment};
use maia_session::rpc::Hub;
use maia_session::session::{self, Config};

fn usage() -> ! {
    eprintln!("usage: maia-session-service --compositor <name> [--without <process>]...\n       \
               maia-session-service --compositor-ready");
    std::process::exit(2)
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let runtime = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
        Ok(runtime) => runtime,
        Err(error) => {
            eprintln!("maia-session-service: {error}");
            return std::process::ExitCode::FAILURE;
        }
    };
    let local = tokio::task::LocalSet::new();

    // From the compositor's [autostart] ($MAIA_SESSION_SCRIPT) it comes without arguments
    let helper = std::env::var("MAIA_SESSION_HELPER").is_ok_and(|v| v == session::READY_HELPER);
    if args.first().map(String::as_str) == Some("--compositor-ready") || (args.is_empty() && helper) {
        return match local.block_on(&runtime, maia_session::ready::report()) {
            Ok(()) => std::process::ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("maia-session-service --compositor-ready: {error}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    let mut compositor = None;
    let mut without = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--compositor" => compositor = Some(args.get(i + 1).cloned().unwrap_or_else(|| usage())),
            "--without" => without.push(args.get(i + 1).cloned().unwrap_or_else(|| usage())),
            "--version" => {
                println!("maia-session-service {}", env!("CARGO_PKG_VERSION"));
                return std::process::ExitCode::SUCCESS;
            }
            _ => usage(),
        }
        i += 2;
    }
    let Some(compositor) = compositor else { usage() };

    match local.block_on(&runtime, run(compositor, without)) {
        Ok(0) => std::process::ExitCode::SUCCESS,
        Ok(code) => std::process::ExitCode::from(code.clamp(1, 255) as u8),
        Err(error) => {
            eprintln!("maia-session-service: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

/// <prefix>: the directory above the one of this program (<prefix>/libexec/maia-session-service)
fn prefix_of(program: &Path) -> Option<PathBuf> {
    program.parent()?.parent().map(Path::to_path_buf)
}

fn socket_path(env: &Environment) -> PathBuf {
    if let Some(path) = env.get("MAIA_SESSION_SOCKET").filter(|p| !p.is_empty()) {
        return PathBuf::from(path);
    }
    let runtime = env.get("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let id = env
        .get("XDG_SESSION_ID")
        .filter(|id| !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric()))
        .cloned()
        .unwrap_or_else(|| format!("pid{}", std::process::id()));
    runtime.join("maia").join(format!("session-{id}.sock"))
}

/// Takes over the socket path, unless another session service still answers there
fn bind(path: &Path) -> std::io::Result<tokio::net::UnixListener> {
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::AddrInUse,
            format!("another maia-session-service already serves {}", path.display()),
        ));
    }
    let _ = std::fs::remove_file(path);
    tokio::net::UnixListener::bind(path)
}

async fn run(compositor: String, without: Vec<String>) -> Result<i32, Box<dyn std::error::Error>> {
    let program = std::env::current_exe()?;
    let mut env: Environment = std::env::vars().collect();

    // What session.toml may use, also for the children
    let prefix = env
        .get("MAIA_PREFIX")
        .cloned()
        .filter(|p| !p.is_empty())
        .or_else(|| prefix_of(&program).map(|p| p.display().to_string()))
        .unwrap_or_default();
    env.insert("MAIA_PREFIX".into(), prefix.clone());
    let version = env
        .get("MAIA_VERSION")
        .cloned()
        .filter(|v| !v.is_empty())
        .or_else(|| option_env!("MAIA_VERSION").map(str::to_string))
        .unwrap_or_default();
    env.insert("MAIA_VERSION".into(), version.clone());
    if !env.contains_key("MAIA_CONFIG_DIR") {
        let config_home = env
            .get("XDG_CONFIG_HOME")
            .cloned()
            .unwrap_or_else(|| format!("{}/.config", env.get("HOME").cloned().unwrap_or_default()));
        env.insert("MAIA_CONFIG_DIR".into(), format!("{config_home}/maia/{version}"));
    }

    let manifest_path = env
        .get("MAIA_SESSION_MANIFEST")
        .cloned()
        .filter(|p| !p.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&prefix).join("etc/maia/session.toml"));
    let lookup = |name: &str| env.get(name).cloned();
    let manifest = Manifest::load(&manifest_path, &lookup)?;
    let compositor_spec = manifest
        .compositors
        .get(&compositor)
        .cloned()
        .ok_or_else(|| format!("{}: no [compositor.{compositor}]", manifest_path.display()))?;

    procs::become_subreaper()?;
    let socket = socket_path(&env);
    let listener = bind(&socket)?;
    let socket_inode = std::fs::metadata(&socket)?.ino();

    let test_mode = env.get("MAIA_SESSION_TEST").is_some_and(|v| v == "1");
    let backend = env.get("MAIA_SESSION_BACKEND").cloned().unwrap_or_else(|| maia_session::power::LOGIND.into());
    eprintln!(
        "maia-session-service {} (Maia {version}, {compositor}, {backend}{}) serves {}; reads {}",
        env!("CARGO_PKG_VERSION"),
        if test_mode { ", test mode" } else { "" },
        socket.display(),
        manifest_path.display()
    );

    let hub = Hub::new(Info {
        maia_version: version,
        compositor: compositor.clone(),
        session_id: env.get("XDG_SESSION_ID").cloned().unwrap_or_default(),
        backend: backend.clone(),
    });
    let config = Config {
        manifest,
        compositor: compositor_spec,
        test_mode,
        without,
        socket_path: socket.clone(),
        ready_command: session::ready_command(&program.display().to_string()),
        program: program.display().to_string(),
        base_env: env,
    };
    let code = session::run(config, listener, hub, &backend).await;

    if std::fs::metadata(&socket).map(|m| m.ino()).ok() == Some(socket_inode) {
        let _ = std::fs::remove_file(&socket);
    }
    Ok(code)
}
