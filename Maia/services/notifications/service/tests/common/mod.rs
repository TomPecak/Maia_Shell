//! Test helpers: a private D-Bus session bus, the service on it, a shell watching it (the
//! NotificationCenter) and Maia senders (the Notifier), all over real connections.

#![allow(dead_code)]

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::io::BufRead;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;

use maia_notifications::hub::{Hub, HubRef};
use maia_notifications::notifications_capnp::{
    self as n, center_listener, notification_center, notification_settings, notifier, notifier_listener, settings_listener,
};
use maia_notifications::rpc::{self, Center, NotifierImpl, SettingsImpl};

pub const TIMEOUT: Duration = Duration::from_secs(5);

pub fn local<F: std::future::Future>(future: F) -> F::Output {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    let local = tokio::task::LocalSet::new();
    let output = local.block_on(&runtime, future);
    // The tasks left (zbus streams) are dropped inside the runtime: their drop spawns a task
    let _entered = runtime.enter();
    drop(local);
    output
}

pub async fn eventually(what: &str, condition: impl Fn() -> bool) {
    let start = Instant::now();
    while !condition() {
        assert!(start.elapsed() < TIMEOUT, "waiting for {what}");
        tokio::time::sleep(Duration::from_millis(2)).await;
    }
}

// --- A private session bus ---

pub struct Bus {
    pub address: String,
    daemon: Child,
}

impl Bus {
    pub fn start() -> Bus {
        let mut daemon = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("dbus-daemon");
        let mut address = String::new();
        std::io::BufReader::new(daemon.stdout.take().unwrap()).read_line(&mut address).unwrap();
        Bus { address: address.trim().to_string(), daemon }
    }

    pub async fn connect(&self) -> zbus::Connection {
        zbus::connection::Builder::address(self.address.as_str()).unwrap().build().await.unwrap()
    }
}

impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.daemon.kill();
        let _ = self.daemon.wait();
    }
}

/// A directory for the images of one test, removed at the end
pub struct TempDir(pub std::path::PathBuf);

impl TempDir {
    pub fn new(name: &str) -> TempDir {
        static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("maia-notifications-{name}-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(dir)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// --- The shell's view ---

#[derive(Clone, Debug, PartialEq)]
pub struct Shown {
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    pub image: String,
    pub actions: Vec<(String, String)>,
    pub urgency: n::Urgency,
    pub popup: bool,
    pub expired: bool,
    pub transient: bool,
    pub inline_reply: bool,
    pub time: i64,
}

/// What a shell has seen, kept like a shell keeps it
#[derive(Default, Debug)]
pub struct Seen {
    pub snapshots: u32,
    pub batches: u32,
    pub notifications: BTreeMap<u32, Shown>,
    /// The ids of the last snapshot, in its order
    pub snapshot_order: Vec<u32>,
    pub dnd_enabled: bool,
    pub dnd_active: bool,
    pub dnd_until: i64,
    pub inhibitors: Vec<String>,
    pub jobs: BTreeMap<u32, ShownJob>,
    pub job_batches: u32,
    /// ShellSettings, from the snapshot and its changes
    pub lock_screen_notifications: Option<bool>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ShownJob {
    pub app_name: String,
    pub desktop_entry: String,
    pub app_icon: String,
    pub title: String,
    pub info_message: String,
    pub state: n::JobState,
    pub percent: i32,
    pub processed_bytes: u64,
    pub total_bytes: u64,
    pub total_files: u64,
    pub speed: u64,
    pub fields: Vec<(String, String)>,
    pub destination: String,
    pub error_code: u32,
    pub error_text: String,
    pub owner_gone: bool,
    pub killable: bool,
    pub suspendable: bool,
}

fn read_job(j: n::job::Reader) -> capnp::Result<(u32, ShownJob)> {
    let mut fields = Vec::new();
    for f in j.get_fields()? {
        fields.push((f.get_label()?.to_string()?, f.get_value()?.to_string()?));
    }
    Ok((
        j.get_id(),
        ShownJob {
            app_name: j.get_app_name()?.to_string()?,
            desktop_entry: j.get_desktop_entry()?.to_string()?,
            app_icon: j.get_app_icon()?.to_string()?,
            title: j.get_title()?.to_string()?,
            info_message: j.get_info_message()?.to_string()?,
            state: j.get_state()?,
            percent: j.get_percent(),
            processed_bytes: j.get_processed_bytes(),
            total_bytes: j.get_total_bytes(),
            total_files: j.get_total_files(),
            speed: j.get_speed(),
            fields,
            destination: j.get_destination()?.to_string()?,
            error_code: j.get_error_code(),
            error_text: j.get_error_text()?.to_string()?,
            owner_gone: j.get_owner_gone(),
            killable: j.get_killable(),
            suspendable: j.get_suspendable(),
        },
    ))
}

fn read(n: n::notification::Reader) -> capnp::Result<(u32, Shown)> {
    let mut actions = Vec::new();
    for a in n.get_actions()? {
        actions.push((a.get_key()?.to_string()?, a.get_label()?.to_string()?));
    }
    Ok((
        n.get_id(),
        Shown {
            app_name: n.get_app_name()?.to_string()?,
            desktop_entry: n.get_desktop_entry()?.to_string()?,
            app_icon: n.get_app_icon()?.to_string()?,
            summary: n.get_summary()?.to_string()?,
            body: n.get_body()?.to_string()?,
            image: n.get_image()?.to_string()?,
            actions,
            urgency: n.get_urgency()?,
            popup: n.get_popup(),
            expired: n.get_expired(),
            transient: n.get_transient(),
            inline_reply: n.get_inline_reply(),
            time: n.get_time(),
        },
    ))
}

fn read_dnd(seen: &mut Seen, d: n::do_not_disturb::Reader) -> capnp::Result<()> {
    seen.dnd_enabled = d.get_enabled();
    seen.dnd_active = d.get_active();
    seen.dnd_until = d.get_until();
    seen.inhibitors = d.get_inhibitors()?.iter().map(|i| Ok(i.get_reason()?.to_string()?)).collect::<capnp::Result<_>>()?;
    Ok(())
}

struct ShellListener(Rc<RefCell<Seen>>);

impl center_listener::Server for ShellListener {
    async fn snapshot(
        self: Rc<Self>,
        params: center_listener::SnapshotParams,
        _: center_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        let snapshot = params.get()?.get_snapshot()?;
        let mut seen = self.0.borrow_mut();
        seen.snapshots += 1;
        seen.lock_screen_notifications = Some(snapshot.get_shell_settings()?.get_lock_screen_notifications());
        seen.notifications.clear();
        seen.snapshot_order.clear();
        for n in snapshot.get_notifications()? {
            let (id, shown) = read(n)?;
            seen.snapshot_order.push(id);
            seen.notifications.insert(id, shown);
        }
        seen.jobs.clear();
        for j in snapshot.get_jobs()? {
            let (id, job) = read_job(j)?;
            seen.jobs.insert(id, job);
        }
        read_dnd(&mut seen, snapshot.get_do_not_disturb()?)
    }

    async fn changes(
        self: Rc<Self>,
        params: center_listener::ChangesParams,
        _: center_listener::ChangesResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let mut seen = self.0.borrow_mut();
        seen.batches += 1;
        for n in params.get_changed()? {
            let (id, shown) = read(n)?;
            seen.notifications.insert(id, shown);
        }
        for id in params.get_removed()? {
            seen.notifications.remove(&id);
        }
        Ok(())
    }

    async fn jobs_changed(
        self: Rc<Self>,
        params: center_listener::JobsChangedParams,
        _: center_listener::JobsChangedResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let mut seen = self.0.borrow_mut();
        seen.job_batches += 1;
        for j in params.get_changed()? {
            let (id, job) = read_job(j)?;
            seen.jobs.insert(id, job);
        }
        for id in params.get_removed()? {
            seen.jobs.remove(&id);
        }
        Ok(())
    }

    async fn do_not_disturb_changed(
        self: Rc<Self>,
        params: center_listener::DoNotDisturbChangedParams,
        _: center_listener::DoNotDisturbChangedResults,
    ) -> Result<(), capnp::Error> {
        read_dnd(&mut self.0.borrow_mut(), params.get()?.get_do_not_disturb()?)
    }

    async fn shell_settings_changed(
        self: Rc<Self>,
        params: center_listener::ShellSettingsChangedParams,
        _: center_listener::ShellSettingsChangedResults,
    ) -> Result<(), capnp::Error> {
        self.0.borrow_mut().lock_screen_notifications = Some(params.get()?.get_settings()?.get_lock_screen_notifications());
        Ok(())
    }
}

fn twoparty<T: capnp::capability::FromClientHook>(stream: tokio::net::UnixStream) -> T {
    let (reader, writer) = stream.compat().split();
    let network = Box::new(twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    ));
    let mut rpc_system = RpcSystem::new(network, None);
    let bootstrap: T = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
    bootstrap
}

pub struct Shell {
    pub seen: Rc<RefCell<Seen>>,
    pub center: notification_center::Client,
    subscription: Option<n::subscription::Client>,
}

impl Shell {
    /// A shell connected to the hub over a socket pair, watching it
    pub async fn connect(hub: &HubRef) -> Shell {
        let (ours, theirs) = tokio::net::UnixStream::pair().unwrap();
        rpc::serve(theirs, Center::client(hub.clone()).client);
        let center: notification_center::Client = twoparty(ours);
        let seen = Rc::new(RefCell::new(Seen::default()));
        let mut request = center.watch_request();
        request.get().set_listener(capnp_rpc::new_client(ShellListener(seen.clone())));
        let subscription = request.send().promise.await.unwrap().get().unwrap().get_subscription().unwrap();
        let shell = Shell { seen, center, subscription: Some(subscription) };
        shell.wait("the snapshot", |s| s.snapshots > 0).await;
        shell
    }

    pub async fn wait(&self, what: &str, condition: impl Fn(&Seen) -> bool) {
        let start = Instant::now();
        while !condition(&self.seen.borrow()) {
            assert!(start.elapsed() < TIMEOUT, "waiting for {what}: {:#?}", self.seen.borrow());
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    }

    pub fn shown(&self, id: u32) -> Option<Shown> {
        self.seen.borrow().notifications.get(&id).cloned()
    }

    pub fn unsubscribe(&mut self) {
        self.subscription = None;
    }

    fn error(result: n::result::Reader) -> n::ErrorCode {
        result.get_error().unwrap()
    }

    pub async fn invoke(&self, id: u32, key: &str, token: &str) -> n::ErrorCode {
        let mut request = self.center.invoke_action_request();
        request.get().set_id(id);
        request.get().set_key(key);
        request.get().set_activation_token(token);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn reply(&self, id: u32, text: &str, token: &str) -> n::ErrorCode {
        let mut request = self.center.reply_request();
        request.get().set_id(id);
        request.get().set_text(text);
        request.get().set_activation_token(token);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn dismiss(&self, id: u32) -> n::ErrorCode {
        let mut request = self.center.dismiss_request();
        request.get().set_id(id);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn expire(&self, id: u32) -> n::ErrorCode {
        let mut request = self.center.expire_request();
        request.get().set_id(id);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn dismiss_all(&self) {
        self.center.dismiss_all_request().send().promise.await.unwrap();
    }

    pub async fn cancel_job(&self, id: u32) -> n::ErrorCode {
        let mut request = self.center.cancel_job_request();
        request.get().set_id(id);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn suspend_job(&self, id: u32, suspended: bool) -> n::ErrorCode {
        let mut request = self.center.suspend_job_request();
        request.get().set_id(id);
        request.get().set_suspended(suspended);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn dismiss_job(&self, id: u32) -> n::ErrorCode {
        let mut request = self.center.dismiss_job_request();
        request.get().set_id(id);
        Shell::error(request.send().promise.await.unwrap().get().unwrap().get_result().unwrap())
    }

    pub async fn set_dnd(&self, enabled: bool, until: i64) {
        let mut request = self.center.set_do_not_disturb_request();
        request.get().set_enabled(enabled);
        request.get().set_until(until);
        request.send().promise.await.unwrap();
    }
}

// --- A Maia sender ---

/// What a sender has heard about its notifications
#[derive(Default, Debug, Clone, PartialEq)]
pub struct Heard {
    pub events: Vec<String>,
}

struct SenderListener(Rc<RefCell<Heard>>);

impl notifier_listener::Server for SenderListener {
    async fn action_invoked(
        self: Rc<Self>,
        params: notifier_listener::ActionInvokedParams,
        _: notifier_listener::ActionInvokedResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        self.0.borrow_mut().events.push(format!("action {} {}", p.get_key()?.to_str()?, p.get_activation_token()?.to_str()?));
        Ok(())
    }

    async fn replied(
        self: Rc<Self>,
        params: notifier_listener::RepliedParams,
        _: notifier_listener::RepliedResults,
    ) -> Result<(), capnp::Error> {
        let p = params.get()?;
        self.0.borrow_mut().events.push(format!("replied {} {}", p.get_text()?.to_str()?, p.get_activation_token()?.to_str()?));
        Ok(())
    }

    async fn closed(
        self: Rc<Self>,
        params: notifier_listener::ClosedParams,
        _: notifier_listener::ClosedResults,
    ) -> Result<(), capnp::Error> {
        let reason = params.get()?.get_reason()?;
        self.0.borrow_mut().events.push(format!("closed {reason:?}"));
        Ok(())
    }
}

pub struct Sender {
    pub notifier: notifier::Client,
}

pub struct Sent {
    pub id: u32,
    pub handle: n::notification_handle::Client,
    pub heard: Rc<RefCell<Heard>>,
}

impl Sent {
    pub async fn hear(&self, what: &str) {
        let start = Instant::now();
        while !self.heard.borrow().events.iter().any(|e| e == what) {
            assert!(start.elapsed() < TIMEOUT, "waiting for \"{what}\": {:?}", self.heard.borrow());
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    }
}

impl Sender {
    pub async fn connect(hub: &HubRef) -> Sender {
        let (ours, theirs) = tokio::net::UnixStream::pair().unwrap();
        rpc::serve(theirs, NotifierImpl::client(hub.clone()).client);
        Sender { notifier: twoparty(ours) }
    }

    pub async fn send(&self, fill: impl FnOnce(n::notification_request::Builder)) -> Sent {
        let heard = Rc::new(RefCell::new(Heard::default()));
        let mut request = self.notifier.notify_request();
        fill(request.get().init_notification());
        request.get().set_listener(capnp_rpc::new_client(SenderListener(heard.clone())));
        let reply = request.send().promise.await.unwrap();
        let reply = reply.get().unwrap();
        Sent { id: reply.get_id(), handle: reply.get_handle().unwrap(), heard }
    }
}

// --- Maia Settings: NotificationSettings ---

#[derive(Clone, Debug, Default, PartialEq)]
pub struct SeenApp {
    pub desktop_entry: String,
    pub app_name: String,
    pub app_icon: String,
    pub enabled: bool,
    pub sent: bool,
    pub declared: bool,
}

#[derive(Default, Debug)]
pub struct SeenSettings {
    pub calls: u32,
    pub dnd_enabled: bool,
    pub dnd_until: i64,
    pub lock_screen_notifications: bool,
    pub apps: BTreeMap<String, SeenApp>,
}

struct SettingsRecorder(Rc<RefCell<SeenSettings>>);

impl settings_listener::Server for SettingsRecorder {
    async fn settings_changed(
        self: Rc<Self>,
        params: settings_listener::SettingsChangedParams,
        _: settings_listener::SettingsChangedResults,
    ) -> Result<(), capnp::Error> {
        let settings = params.get()?.get_settings()?;
        let mut seen = self.0.borrow_mut();
        seen.calls += 1;
        let dnd = settings.get_do_not_disturb()?;
        seen.dnd_enabled = dnd.get_enabled();
        seen.dnd_until = dnd.get_until();
        seen.lock_screen_notifications = settings.get_shell()?.get_lock_screen_notifications();
        seen.apps.clear();
        for a in settings.get_apps()? {
            seen.apps.insert(
                a.get_key()?.to_string()?,
                SeenApp {
                    desktop_entry: a.get_desktop_entry()?.to_string()?,
                    app_name: a.get_app_name()?.to_string()?,
                    app_icon: a.get_app_icon()?.to_string()?,
                    enabled: a.get_enabled(),
                    sent: a.get_sent(),
                    declared: a.get_declared(),
                },
            );
        }
        Ok(())
    }
}

/// Maia Settings: watches the settings and changes them
pub struct SettingsClient {
    pub settings: notification_settings::Client,
    pub seen: Rc<RefCell<SeenSettings>>,
    _subscription: n::subscription::Client,
}

impl SettingsClient {
    pub async fn connect(hub: &HubRef) -> SettingsClient {
        let (ours, theirs) = tokio::net::UnixStream::pair().unwrap();
        rpc::serve(theirs, SettingsImpl::client(hub.clone()).client);
        let settings: notification_settings::Client = twoparty(ours);
        let seen = Rc::new(RefCell::new(SeenSettings::default()));
        let mut request = settings.watch_request();
        request.get().set_listener(capnp_rpc::new_client(SettingsRecorder(seen.clone())));
        let reply = request.send().promise.await.unwrap();
        let subscription = reply.get().unwrap().get_subscription().unwrap();
        let client = SettingsClient { settings, seen, _subscription: subscription };
        client.wait("the first settings", |s| s.calls > 0).await;
        client
    }

    pub async fn wait(&self, what: &str, condition: impl Fn(&SeenSettings) -> bool) {
        let start = Instant::now();
        while !condition(&self.seen.borrow()) {
            assert!(start.elapsed() < TIMEOUT, "waiting for {what}: {:?}", self.seen.borrow());
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    }

    pub async fn set_app_enabled(&self, key: &str, enabled: bool) -> n::ErrorCode {
        let mut request = self.settings.set_app_enabled_request();
        request.get().set_key(key);
        request.get().set_enabled(enabled);
        let reply = request.send().promise.await.unwrap();
        reply.get().unwrap().get_result().unwrap().get_error().unwrap()
    }

    pub async fn set_lock_screen_notifications(&self, enabled: bool) {
        let mut request = self.settings.set_lock_screen_notifications_request();
        request.get().set_enabled(enabled);
        request.send().promise.await.unwrap();
    }

    pub async fn set_do_not_disturb(&self, enabled: bool, until: i64) {
        let mut request = self.settings.set_do_not_disturb_request();
        request.get().set_enabled(enabled);
        request.get().set_until(until);
        request.send().promise.await.unwrap();
    }
}

/// A hub without D-Bus, its images in `dir`
pub fn hub(dir: &TempDir) -> HubRef {
    Hub::new(Some(dir.0.clone()))
}
