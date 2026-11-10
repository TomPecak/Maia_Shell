//! The life of the session: its start, its children, its end.
//!
//! ```text
//!   start      compositor ──► (ready helper reports the display) ──► activation environment
//!              ──► the processes of session.toml in their order ──► running
//!   running    a child ends ──► policy.rs: start it again after a wait, give up, or end the session
//!              the compositor ends ──► the session ends
//!   end        the shell ──► the other children ──► KDE's units ──► the compositor ──► exit
//! ```
//!
//! Everything happens in one thread: the event loop (`run`) handles one Event at a time, and the
//! longer sequences (the start after the compositor is ready, the end, a power action waiting for
//! the administrator's password) are local tasks that never hold a borrow across an await.

use std::cell::RefCell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use std::time::{Duration, Instant};

use futures::future::join_all;
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::{mpsc, oneshot};

use crate::manifest::{Compositor, GiveUpAction, Manifest, Process, Ready, Restart};
use crate::model::{ChildKind, ChildState, ChildView, EndAction, Ending, ErrorCode, Initiator, Outcome, Request, State};
use crate::policy::{Decision, History};
use crate::power::{Action, Power, PowerError, PowerSignal};
use crate::procs::{self, Environment, Exit, Output, Pid};
use crate::rpc::{self, Hub, HubRef, SessionService};

/// What the compositor reports and every child gets from it (and never from the service's own
/// environment, which in a nested session is the outer session's)
pub const DISPLAY_VARIABLES: [&str; 4] = ["WAYLAND_DISPLAY", "DISPLAY", "XAUTHORITY", "WAYFIRE_SOCKET"];

/// Exported to D-Bus activation (and systemd --user, outside test mode), as the session script did
const ACTIVATION_VARIABLES: [&str; 18] = [
    "WAYLAND_DISPLAY", "DISPLAY", "XAUTHORITY", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
    "KDE_FULL_SESSION", "KDE_SESSION_VERSION", "XDG_MENU_PREFIX", "XDG_CONFIG_DIRS", "XDG_DATA_DIRS", "SSH_ASKPASS",
    "SSH_ASKPASS_REQUIRE", "QT_QPA_PLATFORM", "GDK_BACKEND", "QT_WAYLAND_RECONNECT", "MAIA_SESSION_SOCKET",
    "MAIA_COMPOSITOR",
];

const TOOL_TIMEOUT: Duration = Duration::from_secs(10);
const KILL_GRACE: Duration = Duration::from_secs(2);

pub enum Event {
    RestartDue { index: usize, generation: u64 },
    CompositorReady(Vec<(String, String)>),
    ReadyTimeout,
    Request(Request, oneshot::Sender<Outcome>),
    /// The end sequence has finished: leave with this exit code
    Exit(i32),
}

/// How the session runs, from the command line, the environment and session.toml
pub struct Config {
    pub manifest: Manifest,
    pub compositor: Compositor,
    /// MAIA_SESSION_TEST=1: no systemd --user (it belongs to the real session)
    pub test_mode: bool,
    /// --without <name>: processes not to start (e.g. the shell, to run it from a debugger)
    pub without: Vec<String>,
    pub socket_path: PathBuf,
    /// The command that runs the ready helper: "<this program> --compositor-ready"
    pub ready_command: String,
    /// This program: $MAIA_SESSION_SCRIPT of the compositor's [autostart]
    pub program: String,
    /// The environment of the service, the base of every child's
    pub base_env: Environment,
}

struct Child {
    view: ChildView,
    /// None for the compositor
    process: Option<Process>,
    history: History,
    /// Changes with every start, so that an outdated restart timer does nothing
    generation: u64,
    /// restartChild: start it again as soon as it has ended
    restart_now: bool,
    /// A systemd unit that was started (stopped at the end)
    unit_started: bool,
}

pub struct Session {
    config: Config,
    hub: HubRef,
    events: mpsc::UnboundedSender<Event>,
    power: Rc<Power>,
    /// The compositor first, then the processes in the order of session.toml
    children: Vec<Child>,
    display_env: Option<Vec<(String, String)>>,
    waiters: HashMap<Pid, oneshot::Sender<Exit>>,
    state: State,
    ending: Option<Ending>,
    /// A power off or reboot waits for logind (maybe for the password)
    pending_power: bool,
    signals_received: u32,
}

pub type SessionRef = Rc<RefCell<Session>>;

fn log(message: impl AsRef<str>) {
    eprintln!("maia-session-service: {}", message.as_ref());
}

fn shell_quote(text: &str) -> String {
    if !text.is_empty() && text.chars().all(|c| c.is_ascii_alphanumeric() || "/._-+=:@".contains(c)) {
        text.to_string()
    } else {
        format!("'{}'", text.replace('\'', r"'\''"))
    }
}

/// MAIA_SESSION_HELPER of the compositor: this program started without arguments is the ready helper
pub const READY_HELPER: &str = "compositor-ready";

pub fn ready_command(program: &str) -> String {
    format!("{} --compositor-ready", shell_quote(program))
}

impl Session {
    pub fn new(config: Config, hub: HubRef, events: mpsc::UnboundedSender<Event>, power: Rc<Power>) -> SessionRef {
        let mut children = vec![Child {
            view: ChildView::new(&config.compositor.command[0], ChildKind::Compositor),
            process: None,
            history: History::default(),
            generation: 0,
            restart_now: false,
            unit_started: false,
        }];
        for process in &config.manifest.processes {
            if !process.runs_under(&config.compositor.name) || config.without.contains(&process.name) {
                continue;
            }
            if config.test_mode && !process.test_mode {
                continue;
            }
            children.push(Child {
                view: ChildView::new(&process.name, process.kind.into()),
                process: Some(process.clone()),
                history: History::default(),
                generation: 0,
                restart_now: false,
                unit_started: false,
            });
        }
        for child in &children {
            Hub::set_child(&hub, child.view.clone());
        }
        Rc::new(RefCell::new(Session {
            config,
            hub,
            events,
            power,
            children,
            display_env: None,
            waiters: HashMap::new(),
            state: State::Starting,
            ending: None,
            pending_power: false,
            signals_received: 0,
        }))
    }

    fn set_state(&mut self, state: State, ending: Option<Ending>) {
        self.state = state;
        self.ending = ending;
        Hub::set_state(&self.hub, state, ending);
    }

    fn publish(&self, index: usize) {
        Hub::set_child(&self.hub, self.children[index].view.clone());
    }

    /// The environment of a child: the service's, the display of the compositor, the session's
    /// own variables, then what session.toml says for this process
    fn child_env(&self, process: Option<&Process>) -> Environment {
        let mut env = self.config.base_env.clone();
        for name in DISPLAY_VARIABLES {
            env.remove(name);
        }
        for (name, value) in self.display_env.iter().flatten() {
            env.insert(name.clone(), value.clone());
        }
        self.session_variables(&mut env);
        if let Some(process) = process {
            env.extend(process.environment.clone());
            for name in &process.unset_environment {
                env.remove(name);
            }
        }
        env
    }

    fn session_variables(&self, env: &mut Environment) {
        env.insert("MAIA_SESSION_SOCKET".into(), self.config.socket_path.display().to_string());
        env.insert("MAIA_COMPOSITOR".into(), self.config.compositor.name.clone());
        env.remove("MAIA_SESSION_SCRIPT");
        env.remove("MAIA_SESSION_HELPER");
    }

    /// The environment of the compositor: the service's (a nested compositor needs the outer
    /// display), the session's variables and the ready helper for its [autostart]: a single
    /// program, because configurations quote it (maia = "$MAIA_SESSION_SCRIPT"), started without
    /// arguments, so MAIA_SESSION_HELPER tells it what to do
    fn compositor_env(&self) -> Environment {
        let mut env = self.config.base_env.clone();
        self.session_variables(&mut env);
        env.insert("MAIA_SESSION_SCRIPT".into(), self.config.program.clone());
        env.insert("MAIA_SESSION_HELPER".into(), READY_HELPER.into());
        env.extend(self.config.compositor.environment.clone());
        env
    }
}

// --- The start ---

pub fn start(session: &SessionRef) {
    let (command, env, timeout) = {
        let this = session.borrow();
        let mut command = this.config.compositor.command.clone();
        if this.config.compositor.ready == Ready::Argument {
            command.push(this.config.ready_command.clone());
        }
        (command, this.compositor_env(), this.config.compositor.ready_timeout)
    };
    log(format!("starting the compositor: {}", command.join(" ")));
    let name = session.borrow().children[0].view.name.clone();
    match procs::spawn(&name, &command[0], &command[1..], &env, Output::Forward) {
        Ok(pid) => {
            let mut this = session.borrow_mut();
            this.children[0].view.pid = pid as u32;
            this.children[0].view.state = ChildState::Running;
            this.publish(0);
        }
        Err(error) => {
            log(format!("cannot start the compositor {}: {error}", command[0]));
            {
                let mut this = session.borrow_mut();
                this.children[0].view.state = ChildState::Failed;
                this.children[0].view.last_exit = format!("cannot start: {error}");
                this.publish(0);
            }
            end(session, Ending { action: EndAction::Logout, initiator: Initiator::System }, 1);
            return;
        }
    }
    let events = session.borrow().events.clone();
    tokio::task::spawn_local(async move {
        tokio::time::sleep(timeout).await;
        let _ = events.send(Event::ReadyTimeout);
    });
    // What logind offers, meanwhile
    let power = session.borrow().power.clone();
    let hub = session.borrow().hub.clone();
    tokio::task::spawn_local(async move {
        let capabilities = power.capabilities().await;
        Hub::set_capabilities(&hub, capabilities);
    });
}

fn compositor_ready(session: &SessionRef, environment: Vec<(String, String)>) {
    let environment: Vec<(String, String)> =
        environment.into_iter().filter(|(name, _)| DISPLAY_VARIABLES.contains(&name.as_str())).collect();
    let described = environment.iter().map(|(n, v)| format!("{n}={v}")).collect::<Vec<_>>().join(" ");
    let first = {
        let mut this = session.borrow_mut();
        let first = this.display_env.is_none();
        if first {
            this.display_env = Some(environment);
        }
        first && this.state == State::Starting
    };
    if !first {
        // KWin started again by its wrapper runs the helper again, with the same sockets
        log(format!("the compositor reported its display again (restarted?): {described}"));
        return;
    }
    log(format!("the compositor is ready: {described}"));
    let session = session.clone();
    tokio::task::spawn_local(async move { start_processes(&session).await });
}

async fn start_processes(session: &SessionRef) {
    export_activation_environment(session).await;
    let count = session.borrow().children.len();
    for index in 1..count {
        if session.borrow().state != State::Starting {
            return;
        }
        let process = session.borrow().children[index].process.clone().expect("a process");
        if let Some(name) = &process.skip_if_bus_name {
            if bus_name_has_owner(name).await {
                log(format!("{}: not started, {name} already has an owner", process.name));
                let mut this = session.borrow_mut();
                this.children[index].view.state = ChildState::Stopped;
                this.children[index].view.last_exit = format!("not needed: {name} has an owner");
                this.publish(index);
                continue;
            }
        }
        if process.is_unit() {
            start_unit(session, index, &process).await;
        } else {
            spawn_child(session, index);
        }
    }
    let mut this = session.borrow_mut();
    if this.state == State::Starting {
        this.set_state(State::Running, None);
        log("the session runs");
    }
}

/// D-Bus activated services (portals, kded, applications) must know the display
async fn export_activation_environment(session: &SessionRef) {
    let (env, systemd) = {
        let this = session.borrow();
        (this.child_env(None), !this.config.test_mode)
    };
    let mut args: Vec<String> = Vec::new();
    if systemd {
        args.push("--systemd".into());
    }
    args.extend(ACTIVATION_VARIABLES.iter().filter(|name| env.contains_key(**name)).map(|name| name.to_string()));
    match run_tool(session, "dbus-update-activation-environment", &args, &env, Output::Forward).await {
        Some(exit) if exit.success() => {}
        Some(exit) => log(format!("dbus-update-activation-environment: {}", exit.describe())),
        None => log("dbus-update-activation-environment did not finish"),
    }
}

async fn bus_name_has_owner(name: &str) -> bool {
    let Ok(conn) = zbus::Connection::session().await else { return false };
    let reply = conn
        .call_method(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", Some("org.freedesktop.DBus"), "NameHasOwner",
                     &(name,))
        .await;
    reply.and_then(|r| r.body().deserialize::<bool>()).unwrap_or(false)
}

/// A KDE unit through systemctl --user, or the program of its autostart file when the unit is missing
async fn start_unit(session: &SessionRef, index: usize, process: &Process) {
    let unit = process.unit.clone().expect("a unit");
    let env = session.borrow().child_env(Some(process));
    let exists = run_tool(session, "systemctl", &["--user".into(), "cat".into(), unit.clone()], &env, Output::Discard).await;
    if exists.is_some_and(|e| e.success()) {
        log(format!("starting the unit {unit}"));
        let started = run_tool(session, "systemctl", &["--user".into(), "start".into(), "--no-block".into(), unit.clone()],
                               &env, Output::Forward).await;
        let mut this = session.borrow_mut();
        let ok = started.is_some_and(|e| e.success());
        this.children[index].unit_started = ok;
        this.children[index].view.state = if ok { ChildState::Running } else { ChildState::Failed };
        if !ok {
            this.children[index].view.last_exit = "systemctl --user start failed".into();
        }
        this.publish(index);
        return;
    }
    let command = process.autostart.as_deref().and_then(autostart_command);
    match command {
        Some(command) => {
            log(format!("no {unit}, starting from autostart: {}", command.join(" ")));
            let mut fallback = process.clone();
            fallback.command = command;
            fallback.unit = None;
            fallback.restart = Restart::Never;
            session.borrow_mut().children[index].process = Some(fallback);
            spawn_child(session, index);
        }
        None => {
            log(format!("skipping {}: no unit {unit} and no autostart file", process.name));
            let mut this = session.borrow_mut();
            this.children[index].view.state = ChildState::Stopped;
            this.children[index].view.last_exit = "not installed".into();
            this.publish(index);
        }
    }
}

/// The program of /etc/xdg/autostart/<name>.desktop (Exec= without the field codes %u, %f, …)
fn autostart_command(name: &str) -> Option<Vec<String>> {
    let text = std::fs::read_to_string(format!("/etc/xdg/autostart/{name}.desktop")).ok()?;
    let exec = text.lines().find_map(|line| line.strip_prefix("Exec="))?;
    let words: Vec<String> = exec.split_whitespace().filter(|w| !w.starts_with('%')).map(str::to_string).collect();
    (!words.is_empty()).then_some(words)
}

/// Runs a short tool and waits for it (at most TOOL_TIMEOUT); None when it could not run or hangs
async fn run_tool(session: &SessionRef, name: &str, args: &[String], env: &Environment, output: Output) -> Option<Exit> {
    let pid = match procs::spawn(name, name, args, env, output) {
        Ok(pid) => pid,
        Err(error) => {
            log(format!("{name}: {error}"));
            return None;
        }
    };
    let mut exited = wait_for(session, pid);
    match tokio::time::timeout(TOOL_TIMEOUT, &mut exited).await {
        Ok(result) => result.ok(),
        Err(_) => {
            procs::signal_group(pid, libc::SIGKILL);
            None
        }
    }
}

fn wait_for(session: &SessionRef, pid: Pid) -> oneshot::Receiver<Exit> {
    let (sender, receiver) = oneshot::channel();
    session.borrow_mut().waiters.insert(pid, sender);
    receiver
}

fn spawn_child(session: &SessionRef, index: usize) {
    let (name, program, args, env) = {
        let this = session.borrow();
        let child = &this.children[index];
        let process = child.process.as_ref().expect("a process");
        let mut program = process.command[0].clone();
        if !process.search.is_empty() {
            if let Some(found) = procs::first_executable(&process.search) {
                program = found;
            }
        }
        (process.name.clone(), program, process.command[1..].to_vec(), this.child_env(Some(process)))
    };
    match procs::spawn(&name, &program, &args, &env, Output::Forward) {
        Ok(pid) => {
            log(format!("started {name} (pid {pid})"));
            let mut this = session.borrow_mut();
            let child = &mut this.children[index];
            child.view.pid = pid as u32;
            child.view.state = ChildState::Running;
            child.generation += 1;
            this.publish(index);
        }
        Err(error) => {
            log(format!("cannot start {name} ({program}): {error}"));
            ended(session, index, format!("cannot start: {error}"), false);
        }
    }
}

// --- Children that end ---

fn reaped(session: &SessionRef, exits: Vec<(Pid, Exit)>) {
    for (pid, exit) in exits {
        let index = session.borrow().children.iter().position(|c| c.view.pid == pid as u32 && pid > 0);
        if let Some(index) = index {
            {
                let mut this = session.borrow_mut();
                this.children[index].view.pid = 0;
                this.children[index].view.last_exit = exit.describe();
            }
            // Its group may still have members (the client processes of the shell)
            procs::signal_group(pid, libc::SIGTERM);
            ended(session, index, exit.describe(), exit.success());
        }
        let waiter = session.borrow_mut().waiters.remove(&pid);
        if let Some(waiter) = waiter {
            let _ = waiter.send(exit);
        }
    }
}

/// A child is not running any more (ended, or could not be started): what now
fn ended(session: &SessionRef, index: usize, why: String, success: bool) {
    let state = session.borrow().state;
    let name = session.borrow().children[index].view.name.clone();
    if state == State::Ending {
        let mut this = session.borrow_mut();
        this.children[index].view.state = ChildState::Stopped;
        this.publish(index);
        return;
    }
    if index == 0 {
        log(format!("the compositor ended ({why}): the session ends"));
        {
            let mut this = session.borrow_mut();
            this.children[0].view.state = ChildState::Stopped;
            this.publish(0);
        }
        end(session, Ending { action: EndAction::Logout, initiator: Initiator::System }, if success { 0 } else { 1 });
        return;
    }
    let restart_now = std::mem::take(&mut session.borrow_mut().children[index].restart_now);
    if restart_now {
        log(format!("{name} ended ({why}), starting it again as asked"));
        session.borrow_mut().children[index].view.restarts += 1;
        spawn_child(session, index);
        return;
    }
    let decision = {
        let mut this = session.borrow_mut();
        let child = &mut this.children[index];
        let process = child.process.clone().expect("a process");
        child.history.decide(&process, success, Instant::now())
    };
    match decision {
        Decision::Restart(wait) => {
            log(format!("{name} ended ({why}), starting it again in {} s", wait.as_secs()));
            let (events, generation) = {
                let mut this = session.borrow_mut();
                let child = &mut this.children[index];
                child.view.state = ChildState::Restarting;
                child.generation += 1;
                let generation = child.generation;
                this.publish(index);
                (this.events.clone(), generation)
            };
            tokio::task::spawn_local(async move {
                tokio::time::sleep(wait).await;
                let _ = events.send(Event::RestartDue { index, generation });
            });
        }
        Decision::Done => {
            log(format!("{name} ended ({why})"));
            let mut this = session.borrow_mut();
            this.children[index].view.state = ChildState::Stopped;
            this.publish(index);
        }
        Decision::GiveUp(then) => {
            {
                let mut this = session.borrow_mut();
                this.children[index].view.state = ChildState::Failed;
                this.publish(index);
            }
            match then {
                GiveUpAction::EndSession => {
                    log(format!("{name} ended too often ({why}): the session ends"));
                    end(session, Ending { action: EndAction::Logout, initiator: Initiator::System }, 1);
                }
                GiveUpAction::Stop => log(format!("{name} ended too often ({why}): not started again")),
            }
        }
    }
}

fn restart_due(session: &SessionRef, index: usize, generation: u64) {
    let due = {
        let this = session.borrow();
        let child = &this.children[index];
        matches!(this.state, State::Running | State::Starting | State::Sleeping)
            && child.generation == generation
            && child.view.state == ChildState::Restarting
    };
    if due {
        session.borrow_mut().children[index].view.restarts += 1;
        spawn_child(session, index);
    }
}

// --- Requests of the clients ---

fn request(session: &SessionRef, request: Request, reply: oneshot::Sender<Outcome>) {
    match request {
        Request::Logout => {
            if session.borrow().state != State::Running {
                let _ = reply.send(Outcome::error(ErrorCode::Busy, "the session is not running"));
                return;
            }
            log("logout asked");
            let _ = reply.send(Outcome::ok());
            end(session, Ending { action: EndAction::Logout, initiator: Initiator::User }, 0);
        }
        Request::Power(action) => power_action(session, action, reply),
        Request::RestartChild(name) => {
            let outcome = restart_child(session, &name);
            let _ = reply.send(outcome);
        }
    }
}

fn power_action(session: &SessionRef, action: Action, reply: oneshot::Sender<Outcome>) {
    {
        let mut this = session.borrow_mut();
        if this.state != State::Running || this.pending_power {
            let _ = reply.send(Outcome::error(ErrorCode::Busy, "the session is not running or is busy"));
            return;
        }
        if this.hub.borrow().view().capabilities.of(action) == crate::power::Ability::No {
            let _ = reply.send(Outcome::error(ErrorCode::NotSupported, format!("{action:?} is not offered by the system")));
            return;
        }
        this.pending_power = true;
    }
    log(format!("{action:?} asked"));
    let session = session.clone();
    tokio::task::spawn_local(async move {
        let power = session.borrow().power.clone();
        let result = power.act(action).await;
        session.borrow_mut().pending_power = false;
        match result {
            Ok(()) => {
                let _ = reply.send(Outcome::ok());
                if let Some(end_action) = EndAction::of(action) {
                    end(&session, Ending { action: end_action, initiator: Initiator::User }, 0);
                }
            }
            Err(PowerError::NotAllowed(message)) => {
                log(format!("{action:?} not allowed: {message}"));
                let _ = reply.send(Outcome::error(ErrorCode::NotAllowed, message));
            }
            Err(PowerError::Failed(message)) => {
                log(format!("{action:?} failed: {message}"));
                let _ = reply.send(Outcome::error(ErrorCode::Failed, message));
            }
        }
    });
}

fn restart_child(session: &SessionRef, name: &str) -> Outcome {
    let mut this = session.borrow_mut();
    if !matches!(this.state, State::Running | State::Sleeping) {
        return Outcome::error(ErrorCode::Busy, "the session is not running");
    }
    let Some(index) = this.children.iter().position(|c| c.view.name == name) else {
        return Outcome::error(ErrorCode::NotFound, format!("no child {name}"));
    };
    if index == 0 || this.children[index].process.as_ref().is_some_and(|p| p.is_unit()) {
        return Outcome::error(ErrorCode::NotSupported, format!("{name} cannot be restarted here"));
    }
    let child = &mut this.children[index];
    child.history.clear();
    log(format!("restarting {name} as asked"));
    if child.view.pid > 0 {
        child.restart_now = true;
        procs::signal(child.view.pid as Pid, libc::SIGTERM);
        let pid = child.view.pid as Pid;
        let timeout = child.process.as_ref().map(|p| p.stop_timeout).unwrap_or(Duration::from_secs(5));
        drop(this);
        let session = session.clone();
        tokio::task::spawn_local(async move {
            tokio::time::sleep(timeout).await;
            if session.borrow().children[index].view.pid == pid as u32 {
                procs::signal_group(pid, libc::SIGKILL);
            }
        });
    } else {
        child.generation += 1;
        child.view.restarts += 1;
        drop(this);
        spawn_child(session, index);
    }
    Outcome::ok()
}

fn power_signal(session: &SessionRef, signal: PowerSignal) {
    let state = session.borrow().state;
    match signal {
        PowerSignal::PrepareForSleep(true) if state == State::Running => {
            log("the machine goes to sleep");
            session.borrow_mut().set_state(State::Sleeping, None);
        }
        PowerSignal::PrepareForSleep(false) if state == State::Sleeping => {
            log("the machine woke up");
            session.borrow_mut().set_state(State::Running, None);
            let power = session.borrow().power.clone();
            let hub = session.borrow().hub.clone();
            tokio::task::spawn_local(async move {
                let capabilities = power.capabilities().await;
                Hub::set_capabilities(&hub, capabilities);
            });
        }
        PowerSignal::PrepareForShutdown(true) if state != State::Ending => {
            log("the machine is being shut down");
            end(session, Ending { action: EndAction::PowerOff, initiator: Initiator::System }, 0);
        }
        _ => {}
    }
}

// --- The end ---

/// Ends the session in order (once); Event::Exit(code) follows when everything has stopped
pub fn end(session: &SessionRef, ending: Ending, code: i32) {
    {
        let mut this = session.borrow_mut();
        if this.state == State::Ending {
            return;
        }
        log(format!("ending the session ({:?}, {:?})", ending.action, ending.initiator));
        this.set_state(State::Ending, Some(ending));
    }
    let session = session.clone();
    tokio::task::spawn_local(async move {
        end_sequence(&session).await;
        let events = session.borrow().events.clone();
        let _ = events.send(Event::Exit(code));
    });
}

async fn end_sequence(session: &SessionRef) {
    let kinds: Vec<(usize, ChildKind, bool)> = session
        .borrow()
        .children
        .iter()
        .enumerate()
        .map(|(i, c)| (i, c.view.kind, c.unit_started))
        .collect();
    // 1. The shell, while everything it may still talk to runs
    join_all(kinds.iter().filter(|(_, kind, _)| *kind == ChildKind::Shell).map(|(i, _, _)| stop_child(session, *i))).await;
    // 2. The other processes, at once
    join_all(
        kinds
            .iter()
            .filter(|(i, kind, _)| *i > 0 && *kind != ChildKind::Shell)
            .map(|(i, _, _)| stop_child(session, *i)),
    )
    .await;
    // 3. KDE's units
    let units: Vec<String> = kinds
        .iter()
        .filter(|(_, _, started)| *started)
        .filter_map(|(i, _, _)| session.borrow().children[*i].process.as_ref().and_then(|p| p.unit.clone()))
        .collect();
    if !units.is_empty() {
        log(format!("stopping the units {}", units.join(" ")));
        let env = session.borrow().child_env(None);
        let mut args = vec!["--user".to_string(), "stop".to_string()];
        args.extend(units);
        run_tool(session, "systemctl", &args, &env, Output::Forward).await;
        let mut this = session.borrow_mut();
        for (i, _, started) in &kinds {
            if *started {
                this.children[*i].view.state = ChildState::Stopped;
                this.publish(*i);
            }
        }
    }
    // 4. What else lives under the service (applications it adopted), then the compositor
    let me = std::process::id() as Pid;
    let compositor = session.borrow().children[0].view.pid as Pid;
    let orphans: Vec<Pid> = procs::children_of(me).into_iter().filter(|pid| *pid != compositor).collect();
    for pid in &orphans {
        procs::signal(*pid, libc::SIGTERM);
    }
    stop_child(session, 0).await;
    // 5. Anything still there
    tokio::time::sleep(Duration::from_millis(300)).await;
    for pid in procs::children_of(me) {
        procs::signal(pid, libc::SIGKILL);
    }
    log("the session has ended");
}

/// SIGTERM, then after the child's stop_timeout SIGKILL to its whole group
async fn stop_child(session: &SessionRef, index: usize) {
    let (pid, timeout, name) = {
        let this = session.borrow();
        let child = &this.children[index];
        let timeout = match &child.process {
            Some(process) => process.stop_timeout,
            None => this.config.compositor.stop_timeout,
        };
        (child.view.pid as Pid, timeout, child.view.name.clone())
    };
    if pid <= 0 {
        let mut this = session.borrow_mut();
        if !matches!(this.children[index].view.state, ChildState::Stopped | ChildState::Failed) {
            this.children[index].view.state = ChildState::Stopped;
            this.publish(index);
        }
        return;
    }
    let mut exited = wait_for(session, pid);
    procs::signal(pid, libc::SIGTERM);
    if tokio::time::timeout(timeout, &mut exited).await.is_err() {
        log(format!("{name} did not end within {} s: killed", timeout.as_secs()));
        procs::signal_group(pid, libc::SIGKILL);
        let _ = tokio::time::timeout(KILL_GRACE, &mut exited).await;
    }
}

/// A second SIGTERM / SIGINT while ending: no more waiting
fn hurry(session: &SessionRef) -> ! {
    log("asked again to end: killing everything now");
    for child in &session.borrow().children {
        procs::signal_group(child.view.pid as Pid, libc::SIGKILL);
    }
    for pid in procs::children_of(std::process::id() as Pid) {
        procs::signal(pid, libc::SIGKILL);
    }
    std::process::exit(1)
}

// --- The event loop ---

/// Runs the session until it has ended; returns the exit code of the service
pub async fn run(config: Config, listener: tokio::net::UnixListener, hub: HubRef, backend: &str) -> i32 {
    let (events, mut event_queue) = mpsc::unbounded_channel();
    let (power_signals, mut power_queue) = mpsc::unbounded_channel();
    let power = match Power::connect(backend, power_signals).await {
        Ok(power) => power,
        Err(error) => {
            log(format!("logind is not available, no power actions: {error}"));
            Power::Unavailable(error)
        }
    };
    hub.borrow_mut().set_info_backend(power.name());
    let service = SessionService::client(hub.clone(), events.clone());

    let (Ok(mut sigchld), Ok(mut sigterm), Ok(mut sighup), Ok(mut sigint)) = (
        signal(SignalKind::child()),
        signal(SignalKind::terminate()),
        signal(SignalKind::hangup()),
        signal(SignalKind::interrupt()),
    ) else {
        log("cannot handle signals");
        return 1;
    };

    let session = Session::new(config, hub, events, Rc::new(power));
    start(&session);

    loop {
        tokio::select! {
            accepted = listener.accept() => match accepted {
                Ok((stream, _)) => rpc::serve(stream, service.clone()),
                Err(error) => log(format!("accept: {error}")),
            },
            _ = sigchld.recv() => reaped(&session, procs::reap()),
            Some(event) = event_queue.recv() => match event {
                Event::RestartDue { index, generation } => restart_due(&session, index, generation),
                Event::CompositorReady(environment) => compositor_ready(&session, environment),
                Event::ReadyTimeout => {
                    if session.borrow().display_env.is_none() && session.borrow().state == State::Starting {
                        log("the compositor did not report its display in time: the session ends \
                             (does its configuration run $MAIA_SESSION_SCRIPT?)");
                        end(&session, Ending { action: EndAction::Logout, initiator: Initiator::System }, 1);
                    }
                }
                Event::Request(request_, reply) => request(&session, request_, reply),
                Event::Exit(code) => return code,
            },
            Some(signal) = power_queue.recv() => power_signal(&session, signal),
            _ = sigterm.recv() => on_signal(&session, "SIGTERM"),
            _ = sighup.recv() => on_signal(&session, "SIGHUP"),
            _ = sigint.recv() => on_signal(&session, "SIGINT"),
        }
    }
}

fn on_signal(session: &SessionRef, name: &str) {
    let count = {
        let mut this = session.borrow_mut();
        this.signals_received += 1;
        this.signals_received
    };
    if count > 1 && session.borrow().state == State::Ending {
        hurry(session);
    }
    log(format!("{name}: the session ends"));
    end(session, Ending { action: EndAction::Logout, initiator: Initiator::System }, 0);
}
