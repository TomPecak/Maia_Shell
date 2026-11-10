//! The service as a program: a session with a fake compositor, fake processes (small shell
//! scripts) and the fake logind, driven over its real Cap'n Proto socket.
//!
//! Every fake process writes what happens to it into a log file of the test ("start shell",
//! "stop shell", "env shell WAYLAND_DISPLAY=…"), so the tests check the order of the start and the
//! end, the environment and the restarts from outside, as the session would show them.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_session::session_capnp::{self as s, session_listener, session_service};

const TIMEOUT: Duration = Duration::from_secs(10);

/// The fake compositor: runs the ready helper with a display of its own, then waits for SIGTERM
const COMPOSITOR: &str = r#"#!/bin/sh
LOG="$1"; READY="$2"
echo "start compositor" >> "$LOG"
trap 'echo "stop compositor" >> "$LOG"; exit 0' TERM
if [ "$NO_READY" != 1 ]; then
    WAYLAND_DISPLAY=wayland-fake-7 DISPLAY=:77 sh -c "$READY"
fi
while :; do sleep 0.05; done
"#;

/// A fake Wayfire: its [autostart] runs maia = "$MAIA_SESSION_SCRIPT" through sh, quoted, without arguments
const COMPOSITOR_AUTOSTART: &str = r#"#!/bin/sh
LOG="$1"
echo "start compositor" >> "$LOG"
trap 'echo "stop compositor" >> "$LOG"; exit 0' TERM
WAYLAND_DISPLAY=wayland-fake-7 DISPLAY=:77 sh -c '"$MAIA_SESSION_SCRIPT"' &
while :; do sleep 0.05; done
"#;

/// A fake process: run (until SIGTERM), crash (exit 3), crash-once (then run), hang (ignores SIGTERM)
const PROCESS: &str = r#"#!/bin/sh
LOG="$1"; NAME="$2"; MODE="$3"
echo "start $NAME $$" >> "$LOG"
echo "env $NAME WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=$DISPLAY SOCKET=${MAIA_SESSION_SOCKET:+set} EXTRA=$EXTRA" >> "$LOG"
case "$MODE" in
    crash) exit 3 ;;
    crash-once)
        if [ ! -e "$LOG.$NAME.crashed" ]; then touch "$LOG.$NAME.crashed"; exit 3; fi ;;
    hang) trap '' TERM ;;
esac
[ "$MODE" = hang ] || trap 'echo "stop $NAME" >> "$LOG"; exit 0' TERM
while :; do sleep 0.05; done
"#;

static NEXT: AtomicU32 = AtomicU32::new(0);

struct Setup {
    dir: PathBuf,
    service: Child,
}

impl Setup {
    /// A session with these [[process]] entries ("%P" stands for the fake process script, "%L" for the log)
    fn start(processes: &str, compositor_extra: &str, env: &[(&str, &str)]) -> Setup {
        // Short: AF_UNIX paths are limited to about 108 bytes
        let dir = PathBuf::from(format!("/tmp/mst-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let compositor = dir.join("compositor.sh");
        let process = dir.join("process.sh");
        let autostart = compositor_extra.contains("ready = \"autostart\"");
        std::fs::write(&compositor, if autostart { COMPOSITOR_AUTOSTART } else { COMPOSITOR }).unwrap();
        std::fs::write(&process, PROCESS).unwrap();
        let log = dir.join("log");
        std::fs::write(&log, "").unwrap();
        let manifest = format!(
            "version = 1\n[compositor.fake]\ncommand = [\"sh\", \"{}\", \"{}\"]\n{}\n{}",
            compositor.display(),
            log.display(),
            if autostart { compositor_extra.to_string() } else { format!("ready = \"argument\"\n{compositor_extra}") },
            processes.replace("%P", &process.display().to_string()).replace("%L", &log.display().to_string())
        );
        std::fs::write(dir.join("session.toml"), manifest).unwrap();
        let mut command = Command::new(env!("CARGO_BIN_EXE_maia-session-service"));
        command
            .args(["--compositor", "fake"])
            .env("MAIA_SESSION_MANIFEST", dir.join("session.toml"))
            .env("MAIA_SESSION_SOCKET", dir.join("s.sock"))
            .env("MAIA_SESSION_BACKEND", "fake")
            .env("MAIA_SESSION_TEST", "1")
            .env("MAIA_VERSION", "0.0.test")
            // No session bus: the activation export fails at once, as in a bare test
            .env("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
            .env("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/nonexistent")
            // The outer display must not reach the children
            .env("WAYLAND_DISPLAY", "wayland-outer")
            .env("DISPLAY", ":0")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(std::fs::File::create(dir.join("service.log")).unwrap());
        for (name, value) in env {
            command.env(name, value);
        }
        let service = command.spawn().expect("the service");
        Setup { dir, service }
    }

    fn log(&self) -> Vec<String> {
        std::fs::read_to_string(self.dir.join("log")).unwrap_or_default().lines().map(str::to_string).collect()
    }

    fn service_log(&self) -> String {
        std::fs::read_to_string(self.dir.join("service.log")).unwrap_or_default()
    }

    /// The events of the fake processes, without their pids and env lines
    fn events(&self) -> Vec<String> {
        self.log()
            .into_iter()
            .filter(|l| l.starts_with("start ") || l.starts_with("stop "))
            .map(|l| l.split(' ').take(2).collect::<Vec<_>>().join(" "))
            .collect()
    }

    fn wait_log(&self, line: &str) {
        let start = Instant::now();
        while !self.log().iter().any(|l| l.starts_with(line)) {
            assert!(start.elapsed() < TIMEOUT, "no \"{line}\" in {:?}\n{}", self.log(), self.service_log());
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn wait_exit(&mut self) -> i32 {
        let start = Instant::now();
        loop {
            if let Some(status) = self.service.try_wait().unwrap() {
                return status.code().unwrap_or(-1);
            }
            assert!(start.elapsed() < TIMEOUT, "the service did not end\n{}", self.service_log());
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn socket(&self) -> PathBuf {
        self.dir.join("s.sock")
    }
}

impl Drop for Setup {
    fn drop(&mut self) {
        let _ = self.service.kill();
        let _ = self.service.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn process(name: &str, kind: &str, mode: &str, extra: &str) -> String {
    format!(
        "[[process]]\nname = \"{name}\"\nkind = \"{kind}\"\ncommand = [\"sh\", \"%P\", \"%L\", \"{name}\", \"{mode}\"]\n{extra}\n"
    )
}

// --- A client of the contract ---

#[derive(Clone, Debug, Default)]
struct Heard {
    state: Option<s::State>,
    ending: Option<s::EndAction>,
    children: Vec<(String, s::ChildState, u32)>,
}

struct Listener(Rc<RefCell<Heard>>);

fn child_of(child: s::child::Reader) -> capnp::Result<(String, s::ChildState, u32)> {
    Ok((child.get_name()?.to_string()?, child.get_state()?, child.get_restarts()))
}

impl session_listener::Server for Listener {
    async fn snapshot(
        self: Rc<Self>,
        params: session_listener::SnapshotParams,
        _: session_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let mut heard = self.0.borrow_mut();
        heard.state = Some(params.get_state()?);
        for child in params.get_children()? {
            heard.children.push(child_of(child)?);
        }
        Ok(())
    }

    async fn state_changed(
        self: Rc<Self>,
        params: session_listener::StateChangedParams,
        _: session_listener::StateChangedResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let mut heard = self.0.borrow_mut();
        heard.state = Some(params.get_state()?);
        heard.ending = Some(params.get_ending()?.get_action()?);
        Ok(())
    }

    async fn capabilities_changed(
        self: Rc<Self>,
        _: session_listener::CapabilitiesChangedParams,
        _: session_listener::CapabilitiesChangedResults,
    ) -> Result<(), capnp::Error> {
        Ok(())
    }

    async fn child_changed(
        self: Rc<Self>,
        params: session_listener::ChildChangedParams,
        _: session_listener::ChildChangedResults,
    ) -> Result<(), capnp::Error> {
        let child = child_of(params.get()?.get_child()?)?;
        let mut heard = self.0.borrow_mut();
        match heard.children.iter_mut().find(|c| c.0 == child.0) {
            Some(existing) => *existing = child,
            None => heard.children.push(child),
        }
        Ok(())
    }
}

struct Client {
    service: session_service::Client,
    heard: Rc<RefCell<Heard>>,
    _subscription: s::subscription::Client,
}

async fn connect(socket: &Path) -> Client {
    let start = Instant::now();
    let stream = loop {
        match tokio::net::UnixStream::connect(socket).await {
            Ok(stream) => break stream,
            Err(_) if start.elapsed() < TIMEOUT => tokio::time::sleep(Duration::from_millis(20)).await,
            Err(error) => panic!("{}: {error}", socket.display()),
        }
    };
    let (reader, writer) = stream.compat().split();
    let network = Box::new(twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    ));
    let mut rpc_system = RpcSystem::new(network, None);
    let service: session_service::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
    let heard = Rc::new(RefCell::new(Heard::default()));
    let mut request = service.watch_request();
    request.get().set_listener(capnp_rpc::new_client(Listener(heard.clone())));
    let subscription = request.send().promise.await.unwrap().get().unwrap().get_subscription().unwrap();
    Client { service, heard, _subscription: subscription }
}

impl Client {
    async fn wait<F: Fn(&Heard) -> bool>(&self, what: &str, condition: F) {
        let start = Instant::now();
        while !condition(&self.heard.borrow()) {
            assert!(start.elapsed() < TIMEOUT, "waiting for {what}: {:?}", self.heard.borrow());
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }

    async fn running(&self) {
        self.wait("running", |h| h.state == Some(s::State::Running)).await;
    }

    async fn control(&self) -> s::session_control::Client {
        self.service.control_request().send().promise.await.unwrap().get().unwrap().get_control().unwrap()
    }

    async fn logout(&self) -> s::ErrorCode {
        let control = self.control().await;
        let reply = control.logout_request().send().promise.await.unwrap();
        reply.get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    async fn power_off(&self) -> s::ErrorCode {
        let control = self.control().await;
        let reply = control.power_off_request().send().promise.await.unwrap();
        reply.get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    fn child(&self, name: &str) -> Option<(s::ChildState, u32)> {
        self.heard.borrow().children.iter().find(|c| c.0 == name).map(|c| (c.1, c.2))
    }
}

fn local<F: std::future::Future>(future: F) -> F::Output {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    tokio::task::LocalSet::new().block_on(&runtime, future)
}

// --- The tests ---

#[test]
fn starts_in_order_and_logs_out_in_reverse() {
    let processes = [
        process("helper", "helper", "run", ""),
        process("service", "maia-service", "run", "restart = \"always\"\nenvironment = { EXTRA = \"x\" }"),
        process("shell", "shell", "run", "restart = \"always\""),
    ]
    .concat();
    let mut setup = Setup::start(&processes, "", &[]);
    local(async {
        let client = connect(&setup.socket()).await;
        client.running().await;
        setup.wait_log("start shell");
        assert_eq!(setup.events(), ["start compositor", "start helper", "start service", "start shell"]);
        // The display of the compositor, never the outer one; the session socket; the process's own variables
        let env: Vec<String> = setup.log().into_iter().filter(|l| l.starts_with("env ")).collect();
        for line in &env {
            assert!(line.contains("WAYLAND_DISPLAY=wayland-fake-7 DISPLAY=:77 SOCKET=set"), "{line}");
        }
        assert!(env.iter().any(|l| l.starts_with("env service") && l.ends_with("EXTRA=x")), "{env:?}");

        assert_eq!(client.logout().await, s::ErrorCode::None);
        client.wait("ending", |h| h.state == Some(s::State::Ending)).await;
    });
    assert_eq!(setup.wait_exit(), 0);
    let events = setup.events();
    let stop = |name: &str| events.iter().position(|e| *e == format!("stop {name}")).unwrap_or_else(|| panic!("{events:?}"));
    // The shell first, the compositor last
    assert!(stop("shell") < stop("service") && stop("shell") < stop("helper"), "{events:?}");
    assert_eq!(events.last().map(String::as_str), Some("stop compositor"), "{events:?}");
}

#[test]
fn a_crashed_service_comes_back() {
    let processes = [
        process("service", "maia-service", "crash-once", "restart = \"always\""),
        process("shell", "shell", "run", "restart = \"always\""),
    ]
    .concat();
    let setup = Setup::start(&processes, "", &[]);
    local(async {
        let client = connect(&setup.socket()).await;
        client
            .wait("the service restarted", |h| {
                h.children.iter().any(|c| c.0 == "service" && c.1 == s::ChildState::Running && c.2 == 1)
            })
            .await;
        assert_eq!(setup.events().iter().filter(|e| *e == "start service").count(), 2);
        assert_eq!(client.child("shell").map(|c| c.0), Some(s::ChildState::Running));
    });
}

#[test]
fn a_shell_that_keeps_crashing_ends_the_session() {
    let processes = [
        process("service", "maia-service", "run", "restart = \"always\""),
        process("shell", "shell", "crash", "restart = \"always\"\ngive_up = { crashes = 2, within = 60, then = \"end-session\" }"),
    ]
    .concat();
    let mut setup = Setup::start(&processes, "", &[]);
    assert_eq!(setup.wait_exit(), 1);
    let events = setup.events();
    assert_eq!(events.iter().filter(|e| *e == "start shell").count(), 2, "{events:?}");
    assert!(events.contains(&"stop service".to_string()) && events.contains(&"stop compositor".to_string()), "{events:?}");
}

#[test]
fn power_off_ends_the_session_after_logind_accepted() {
    let mut setup = Setup::start(&process("shell", "shell", "run", "restart = \"always\""), "", &[]);
    local(async {
        let client = connect(&setup.socket()).await;
        client.running().await;
        assert_eq!(client.power_off().await, s::ErrorCode::None);
        client.wait("ending", |h| h.ending == Some(s::EndAction::PowerOff)).await;
    });
    assert_eq!(setup.wait_exit(), 0);
    assert!(setup.service_log().contains("fake logind: PowerOff"), "{}", setup.service_log());
}

#[test]
fn a_refused_power_off_leaves_the_session_running() {
    let setup = Setup::start(&process("shell", "shell", "run", "restart = \"always\""), "", &[("MAIA_SESSION_FAKE_LOGIND", "deny")]);
    local(async {
        let client = connect(&setup.socket()).await;
        client.running().await;
        assert_eq!(client.power_off().await, s::ErrorCode::NotAllowed);
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(client.heard.borrow().state, Some(s::State::Running));
        // The next request is not blocked by the refused one
        assert_eq!(client.power_off().await, s::ErrorCode::NotAllowed);
    });
    assert!(!setup.events().contains(&"stop shell".to_string()));
}

#[test]
fn a_compositor_that_never_reports_ends_the_session() {
    let mut setup = Setup::start(&process("shell", "shell", "run", ""), "ready_timeout = 1", &[("NO_READY", "1")]);
    let started = Instant::now();
    assert_eq!(setup.wait_exit(), 1);
    assert!(started.elapsed() < Duration::from_secs(5));
    assert!(!setup.events().contains(&"start shell".to_string()));
    assert!(setup.service_log().contains("did not report its display"), "{}", setup.service_log());
}

#[test]
fn a_hanging_process_does_not_hold_up_the_logout() {
    let processes = [
        process("stubborn", "maia-service", "hang", "stop_timeout = 1"),
        process("shell", "shell", "run", ""),
    ]
    .concat();
    let mut setup = Setup::start(&processes, "", &[]);
    local(async {
        let client = connect(&setup.socket()).await;
        client.running().await;
        assert_eq!(client.logout().await, s::ErrorCode::None);
    });
    let started = Instant::now();
    assert_eq!(setup.wait_exit(), 0);
    assert!(started.elapsed() < Duration::from_secs(6), "{:?}", started.elapsed());
    assert!(setup.service_log().contains("stubborn did not end within 1 s"), "{}", setup.service_log());
}

#[test]
fn sigterm_ends_the_session_in_order() {
    let mut setup = Setup::start(&process("shell", "shell", "run", ""), "", &[]);
    local(async {
        connect(&setup.socket()).await.running().await;
    });
    // SAFETY: kill with plain values
    unsafe { libc::kill(setup.service.id() as i32, libc::SIGTERM) };
    assert_eq!(setup.wait_exit(), 0);
    assert_eq!(setup.events(), ["start compositor", "start shell", "stop shell", "stop compositor"]);
}

#[test]
fn nothing_outlives_a_killed_service() {
    let mut setup = Setup::start(&process("shell", "shell", "run", ""), "", &[]);
    local(async {
        connect(&setup.socket()).await.running().await;
    });
    setup.wait_log("start shell");
    let pid: i32 = setup.log().iter().find(|l| l.starts_with("start shell")).unwrap().split(' ').nth(2).unwrap().parse().unwrap();
    setup.service.kill().unwrap();
    setup.wait_exit();
    let start = Instant::now();
    // SAFETY: kill with signal 0 only checks whether the process is there
    while unsafe { libc::kill(pid, 0) } == 0 {
        assert!(start.elapsed() < TIMEOUT, "the shell (pid {pid}) outlived the service");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn a_compositor_with_autostart_runs_the_helper_without_arguments() {
    let setup = Setup::start(&process("shell", "shell", "run", ""), "ready = \"autostart\"", &[]);
    local(async {
        connect(&setup.socket()).await.running().await;
    });
    setup.wait_log("start shell");
    let env: Vec<String> = setup.log().into_iter().filter(|l| l.starts_with("env shell")).collect();
    assert!(env[0].contains("WAYLAND_DISPLAY=wayland-fake-7"), "{env:?}");
}
