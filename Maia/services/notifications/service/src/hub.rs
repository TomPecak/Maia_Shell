//! The hub: the list of notifications (model.rs) shared by every door of the service, its
//! listeners (the shells) and the senders' events.
//!
//! ```text
//!   D-Bus (dbus.rs) ──DbusCall──┐                         ┌──► CenterListener (shells): snapshot,
//!   Notifier (rpc.rs) ──────────┼──► Hub: Store + rules ──┤    then one batch per frame
//!   NotificationCenter (rpc.rs) ┘                         └──► senders: ActionInvoked, Replied, Closed
//!                                                               (D-Bus signals to the sender only,
//!                                                                or its NotifierListener)
//! ```
//!
//! Changes go to the shells in batches: a change marks the notification, the batch goes out at the
//! next frame (16 ms after the previous batch at the earliest). A flood of notifications is one
//! model update per frame in the shell, and the latest content of each notification only.
//!
//! Everything runs in the service's one thread; nothing here waits: images are written on tokio's
//! blocking threads, calls to listeners and D-Bus signals are sent in the background, in order.

use std::cell::RefCell;
use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use futures::FutureExt;
use tokio::sync::mpsc;

use crate::image;
use crate::jobs::{self, Ended, JobRequest, JobStore, JobUpdate};
use crate::model::{CloseReason, Expired, Inhibitor, Request, Store, now_ms};
use crate::throttle::ChangeThrottle;
use crate::notifications_capnp::{center_listener, job_listener, notifier_listener, settings_listener};
use crate::settings::Settings;
use crate::rpc;

/// The shortest time between two batches to the shells: one frame
pub const FRAME: Duration = Duration::from_millis(16);

/// A notification of an application the user turned off is closed this long after it came, so
/// that its sender has its id first (on D-Bus the answer and the signal take different ways)
pub const REJECTED_CLOSE_DELAY: Duration = Duration::from_millis(100);

/// Settings are written this long after they change: a burst of changes is one write
pub const SETTINGS_SAVE_DELAY: Duration = Duration::from_millis(300);

/// Who gets the events of a notification
#[derive(Clone)]
pub enum Origin {
    /// A D-Bus client, by its unique name: its signals are sent to it only
    DBus(String),
    /// A Notifier client
    Maia(notifier_listener::Client),
    /// Nobody (internal, tests)
    Nobody,
}

impl std::fmt::Debug for Origin {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Origin::DBus(name) => write!(f, "DBus({name})"),
            Origin::Maia(_) => write!(f, "Maia"),
            Origin::Nobody => write!(f, "Nobody"),
        }
    }
}

/// What a sender hears about its notification. The token is an xdg-activation token for raising
/// the sender's window ("" none); on D-Bus it goes first as its own signal (ActivationToken).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SenderEvent {
    ActionInvoked { key: String, token: String },
    Replied { text: String, token: String },
    Closed(CloseReason),
}

/// What the hub asks the D-Bus side to send (dbus.rs sends them in this order)
#[derive(Debug)]
pub enum Outgoing {
    Signal { destination: String, id: u32, event: SenderEvent },
    InhibitedChanged,
    /// The shell asks a job's application to cancel, pause or go on
    JobRequest { id: u32, kind: crate::dbus_jobs::JobRequestKind },
    /// A job is over for its application: its D-Bus objects go
    JobGone(u32),
    /// org.kde.kuiserver's jobUrlsChanged: where the running jobs write to
    JobUrls(Vec<String>),
}

/// The shortest time between two changes of one job to the shells
pub const JOB_INTERVAL: Duration = Duration::from_millis(250);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorCode {
    NotFound,
    InvalidArgument,
    Unavailable,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OpError {
    pub code: ErrorCode,
    pub message: String,
}

impl OpError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> OpError {
        OpError { code, message: message.into() }
    }

    fn not_found(id: u32) -> OpError {
        OpError::new(ErrorCode::NotFound, format!("no notification {id}"))
    }
}

pub struct Hub {
    store: Store<Origin>,
    listeners: Vec<(u64, center_listener::Client)>,
    next_listener: u64,
    // The batch being collected
    changed: BTreeSet<u32>,
    removed: Vec<u32>,
    dnd_changed: bool,
    flush_scheduled: bool,
    last_flush: Option<Instant>,
    image_dir: Option<PathBuf>,
    dbus_out: Option<mpsc::UnboundedSender<Outgoing>>,
    /// Read by the D-Bus property "Inhibited" (another thread may read it)
    inhibited: Arc<AtomicBool>,
    /// Bumped by every change of do not disturb: an older "until" timer does nothing
    dnd_timer: u64,
    jobs: JobStore,
    jobs_changed: BTreeSet<u32>,
    jobs_removed: Vec<u32>,
    job_throttle: ChangeThrottle,
    /// The last jobUrlsChanged sent
    job_urls: Vec<String>,
    /// Jobs of Maia senders (Notifier.startJob): what the user asks goes to them, not to D-Bus
    job_listeners: HashMap<u32, job_listener::Client>,
    /// The user's rules (settings.rs), saved to `settings_path` a moment after they change
    settings: Settings,
    settings_path: Option<PathBuf>,
    save_scheduled: bool,
    /// The desktop entries (desktop.rs), read once at start: they name new senders
    entries: Rc<HashMap<String, crate::desktop::Entry>>,
    settings_listeners: Vec<(u64, settings_listener::Client)>,
    settings_changed: bool,
    shell_settings_changed: bool,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    /// image_dir: where pixels are written as PNG (None: notifications with pixels go without them)
    pub fn new(image_dir: Option<PathBuf>) -> HubRef {
        Hub::with_store(Store::new(), image_dir)
    }

    pub fn with_store(store: Store<Origin>, image_dir: Option<PathBuf>) -> HubRef {
        Rc::new(RefCell::new(Hub {
            store,
            listeners: Vec::new(),
            next_listener: 0,
            changed: BTreeSet::new(),
            removed: Vec::new(),
            dnd_changed: false,
            flush_scheduled: false,
            last_flush: None,
            image_dir,
            dbus_out: None,
            inhibited: Arc::new(AtomicBool::new(false)),
            dnd_timer: 0,
            jobs: JobStore::new(),
            jobs_changed: BTreeSet::new(),
            jobs_removed: Vec::new(),
            job_throttle: ChangeThrottle::new(JOB_INTERVAL),
            job_urls: Vec::new(),
            job_listeners: HashMap::new(),
            settings: Settings::default(),
            settings_path: None,
            save_scheduled: false,
            entries: Rc::new(HashMap::new()),
            settings_listeners: Vec::new(),
            settings_changed: false,
            shell_settings_changed: false,
        }))
    }

    pub fn store(&self) -> &Store<Origin> {
        &self.store
    }

    pub fn jobs(&self) -> &JobStore {
        &self.jobs
    }

    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    pub fn inhibited_flag(&self) -> Arc<AtomicBool> {
        self.inhibited.clone()
    }

    pub fn set_dbus_out(&mut self, out: mpsc::UnboundedSender<Outgoing>) {
        self.dbus_out = Some(out);
    }

    // --- Senders ---

    /// A new notification or a replacement; answers at once with its id
    pub fn notify(hub: &HubRef, replaces: u32, request: Request, origin: Origin) -> u32 {
        let mut this = hub.borrow_mut();
        if let Some(key) = Settings::key_of(&request.desktop_entry, &request.app_name) {
            let entries = this.entries.clone();
            let entry = entries.get(&request.desktop_entry);
            if this.settings.sent(&key, &request.desktop_entry, &request.app_name, &request.app_icon, entry) {
                this.settings_did_change(hub);
                schedule_flush(hub, &mut this);
            }
            if !this.settings.allows(&key) {
                // Turned off by the user: not shown, not kept. The sender gets an id like any other
                // and hears that it is closed once it has it (its Notify call answered first)
                let id = this.store.reserve_id();
                let weak = Rc::downgrade(hub);
                tokio::task::spawn_local(async move {
                    tokio::time::sleep(REJECTED_CLOSE_DELAY).await;
                    if let Some(hub) = weak.upgrade() {
                        hub.borrow().tell(&origin, id, SenderEvent::Closed(CloseReason::Other));
                    }
                });
                return id;
            }
        }
        let added = this.store.add(replaces, request, origin, now_ms());
        let id = added.id;
        if let Some(file) = added.old_image_file {
            discard(file);
        }
        for (dropped, origin, file) in added.dropped {
            this.mark_removed(dropped);
            if let Some(file) = file {
                discard(file);
            }
            this.tell(&origin, dropped, SenderEvent::Closed(CloseReason::Other));
        }
        match added.pixels {
            None => this.mark_changed(id),
            Some(pixels) => {
                // A replacement keeps its old content on screen until the new one is ready
                write_image(hub, this.image_dir.clone(), id, added.generation, pixels);
            }
        }
        schedule_flush(hub, &mut this);
        id
    }

    /// The sender closes its notification (CloseNotification, NotificationHandle.close)
    pub fn close_by_app(hub: &HubRef, id: u32) -> bool {
        let mut this = hub.borrow_mut();
        let closed = this.close(id, CloseReason::ClosedByApp);
        schedule_flush(hub, &mut this);
        closed
    }

    // --- The shell ---

    pub fn invoke_action(hub: &HubRef, id: u32, key: &str, token: &str) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        let entry = this.store.get(id).ok_or_else(|| OpError::not_found(id))?;
        if !entry.notification.has_action(key) {
            return Err(OpError::new(ErrorCode::InvalidArgument, format!("notification {id} has no action \"{key}\"")));
        }
        let origin = entry.origin.clone();
        let resident = entry.notification.resident;
        this.tell(&origin, id, SenderEvent::ActionInvoked { key: key.to_string(), token: token.to_string() });
        if !resident {
            this.close(id, CloseReason::Dismissed);
        }
        schedule_flush(hub, &mut this);
        Ok(())
    }

    pub fn reply(hub: &HubRef, id: u32, text: &str, token: &str) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        let entry = this.store.get(id).ok_or_else(|| OpError::not_found(id))?;
        if !entry.notification.inline_reply {
            return Err(OpError::new(ErrorCode::InvalidArgument, format!("notification {id} takes no reply")));
        }
        let origin = entry.origin.clone();
        let resident = entry.notification.resident;
        this.tell(&origin, id, SenderEvent::Replied { text: text.to_string(), token: token.to_string() });
        if !resident {
            this.close(id, CloseReason::Dismissed);
        }
        schedule_flush(hub, &mut this);
        Ok(())
    }

    pub fn dismiss(hub: &HubRef, id: u32) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        if !this.close(id, CloseReason::Dismissed) {
            return Err(OpError::not_found(id));
        }
        schedule_flush(hub, &mut this);
        Ok(())
    }

    /// The popup of a notification has ended
    pub fn expire(hub: &HubRef, id: u32) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        match this.store.expire(id) {
            Expired::NotFound => return Err(OpError::not_found(id)),
            Expired::Kept => this.mark_changed(id),
            Expired::Removed(entry) => {
                if entry.ready {
                    this.mark_removed(id);
                }
                if let Some(file) = entry.image_file {
                    discard(file);
                }
                this.tell(&entry.origin, id, SenderEvent::Closed(CloseReason::Expired));
            }
        }
        schedule_flush(hub, &mut this);
        Ok(())
    }

    pub fn dismiss_all(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        for id in this.store.dismissable() {
            this.close(id, CloseReason::Dismissed);
        }
        schedule_flush(hub, &mut this);
    }

    /// until: ms since 1970, 0 = until turned off
    pub fn set_do_not_disturb(hub: &HubRef, enabled: bool, until: i64) {
        let mut this = hub.borrow_mut();
        this.settings.dnd_enabled = enabled;
        this.settings.dnd_until = if enabled { until.max(0) } else { 0 };
        this.settings_did_change(hub);
        this.store.dnd.enabled = enabled;
        this.store.dnd.until = if enabled { until.max(0) } else { 0 };
        this.dnd_timer += 1;
        if enabled && until > 0 {
            let timer = this.dnd_timer;
            let weak = Rc::downgrade(hub);
            let wait = Duration::from_millis((until - now_ms()).max(0) as u64);
            tokio::task::spawn_local(async move {
                tokio::time::sleep(wait).await;
                let Some(hub) = weak.upgrade() else { return };
                let mut this = hub.borrow_mut();
                if this.dnd_timer == timer {
                    // Its time has run out: off, for everyone to see
                    this.store.dnd.enabled = false;
                    this.store.dnd.until = 0;
                    this.settings.dnd_enabled = false;
                    this.settings.dnd_until = 0;
                    this.settings_did_change(&hub);
                    this.dnd_did_change();
                    schedule_flush(&hub, &mut this);
                }
            });
        }
        this.dnd_did_change();
        schedule_flush(hub, &mut this);
    }

    // --- Inhibitions (KDE's Inhibit on D-Bus) ---

    pub fn inhibit(hub: &HubRef, inhibitor: Inhibitor) -> u32 {
        let mut this = hub.borrow_mut();
        let cookie = this.store.inhibit(inhibitor);
        this.dnd_did_change();
        schedule_flush(hub, &mut this);
        cookie
    }

    pub fn uninhibit(hub: &HubRef, cookie: u32) {
        let mut this = hub.borrow_mut();
        if this.store.uninhibit(cookie) {
            this.dnd_did_change();
            schedule_flush(hub, &mut this);
        }
    }

    /// A D-Bus client left the bus: its inhibitions end, its running jobs have failed
    pub fn owner_gone(hub: &HubRef, name: &str) {
        let mut this = hub.borrow_mut();
        if this.store.owner_gone(name) {
            this.dnd_did_change();
        }
        for id in this.jobs.owner_gone(name) {
            this.job_ended(id);
            this.send_out(Outgoing::JobGone(id));
        }
        this.check_job_urls();
        schedule_flush(hub, &mut this);
    }

    // --- Jobs (dbus_jobs.rs, jobs.rs) ---

    /// A new job; shown after its delay (or as soon as an "immediate" one has a title)
    pub fn create_job(hub: &HubRef, owner: &str, request: JobRequest) -> u32 {
        let mut this = hub.borrow_mut();
        let delay = if request.immediate { jobs::SHOW_DELAY_IMMEDIATE } else { jobs::SHOW_DELAY };
        let id = this.jobs.create(request, owner);
        if this.jobs.get(id).is_some_and(|e| e.visible) {
            this.job_shown(id);
        }
        let weak = Rc::downgrade(hub);
        tokio::task::spawn_local(async move {
            tokio::time::sleep(delay).await;
            let Some(hub) = weak.upgrade() else { return };
            let mut this = hub.borrow_mut();
            if this.jobs.show(id) {
                this.job_shown(id);
                schedule_flush(&hub, &mut this);
            }
        });
        this.check_job_urls();
        schedule_flush(hub, &mut this);
        id
    }

    /// A job of a Maia sender, which hears the user's requests through `listener`
    pub fn create_maia_job(hub: &HubRef, request: JobRequest, listener: job_listener::Client) -> u32 {
        let id = Hub::create_job(hub, "", request);
        hub.borrow_mut().job_listeners.insert(id, listener);
        id
    }

    /// A Maia sender let go of its job without ending it: failed
    pub fn abandon_job(hub: &HubRef, id: u32) {
        let mut this = hub.borrow_mut();
        let ended = this.jobs.abandon(id);
        if ended != Ended::NotFound {
            this.job_end(id, ended);
            schedule_flush(hub, &mut this);
        }
    }

    /// Whether a job still runs (a sender's update to an ended one is refused)
    pub fn job_running(&self, id: u32) -> bool {
        self.jobs.get(id).is_some_and(|e| !e.job.state.ended())
    }

    pub fn update_job(hub: &HubRef, id: u32, update: JobUpdate) {
        let mut this = hub.borrow_mut();
        let was_visible = this.jobs.get(id).is_some_and(|e| e.visible);
        if this.jobs.update(id, update) {
            if was_visible {
                this.job_changed(id);
            } else {
                this.job_shown(id);
            }
            this.check_job_urls();
            schedule_flush(hub, &mut this);
        }
    }

    pub fn set_job_error(hub: &HubRef, id: u32, code: u32) {
        hub.borrow_mut().jobs.set_error(id, code);
    }

    /// The application ended the job
    pub fn terminate_job(hub: &HubRef, id: u32, code: u32, text: &str) {
        let mut this = hub.borrow_mut();
        let ended = this.jobs.terminate(id, code, text);
        this.job_end(id, ended);
        schedule_flush(hub, &mut this);
    }

    /// The user cancels a job: its application is asked, and the job ends anyway when it does not
    /// answer within CANCEL_GRACE
    pub fn cancel_job(hub: &HubRef, id: u32) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        if this.jobs.get(id).is_none() {
            return Err(OpError::not_found(id));
        }
        if !this.jobs.request_cancel(id) {
            return Err(OpError::new(ErrorCode::InvalidArgument, format!("job {id} cannot be canceled")));
        }
        this.ask_job(id, crate::dbus_jobs::JobRequestKind::Cancel);
        let weak = Rc::downgrade(hub);
        tokio::task::spawn_local(async move {
            tokio::time::sleep(jobs::CANCEL_GRACE).await;
            let Some(hub) = weak.upgrade() else { return };
            let mut this = hub.borrow_mut();
            let ended = this.jobs.cancel_timed_out(id);
            if ended != Ended::NotFound {
                this.job_end(id, ended);
                schedule_flush(&hub, &mut this);
            }
        });
        Ok(())
    }

    /// The user pauses or resumes a job; its state changes when its application reports it
    pub fn suspend_job(hub: &HubRef, id: u32, suspended: bool) -> Result<(), OpError> {
        let this = hub.borrow_mut();
        let entry = this.jobs.get(id).ok_or_else(|| OpError::not_found(id))?;
        if !entry.job.suspendable || entry.job.state.ended() {
            return Err(OpError::new(ErrorCode::InvalidArgument, format!("job {id} cannot be paused")));
        }
        let kind = if suspended { crate::dbus_jobs::JobRequestKind::Suspend } else { crate::dbus_jobs::JobRequestKind::Resume };
        this.ask_job(id, kind);
        Ok(())
    }

    /// The user dismisses an ended job
    pub fn dismiss_job(hub: &HubRef, id: u32) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        match this.jobs.dismiss(id) {
            Some(was_visible) => {
                if was_visible {
                    this.job_removed(id);
                }
                schedule_flush(hub, &mut this);
                Ok(())
            }
            None if this.jobs.get(id).is_some() => Err(OpError::new(ErrorCode::InvalidArgument, format!("job {id} still runs"))),
            None => Err(OpError::not_found(id)),
        }
    }

    /// org.kde.kuiserver's emitJobUrlsChanged: a file manager asks where the running jobs write to
    pub fn emit_job_urls(hub: &HubRef) {
        let this = hub.borrow();
        this.send_out(Outgoing::JobUrls(this.jobs.running_urls()));
    }

    // --- Settings (settings.rs) ---

    /// The rules kept in `path`, and the applications the desktop entries in `data_dirs` declare
    /// (read in the background; the list grows when they are read)
    pub fn load_settings(hub: &HubRef, path: PathBuf, data_dirs: Vec<PathBuf>) {
        let settings = Settings::load(&path);
        let (enabled, until) = (settings.dnd_enabled, settings.dnd_until);
        {
            let mut this = hub.borrow_mut();
            this.settings = settings;
            this.settings_path = Some(path);
        }
        if enabled && (until == 0 || until > now_ms()) {
            Hub::set_do_not_disturb(hub, true, until);
        } else if enabled {
            // Its time ran out while the session was away
            Hub::set_do_not_disturb(hub, false, 0);
        }
        let weak = Rc::downgrade(hub);
        tokio::task::spawn_local(async move {
            let read = tokio::task::spawn_blocking(move || {
                let languages = crate::desktop::languages();
                let entries = crate::desktop::index(&data_dirs, &languages);
                let declared = crate::desktop::declared(&data_dirs, &entries, &languages);
                (entries, declared)
            });
            let Ok((entries, declared)) = read.await else { return };
            let Some(hub) = weak.upgrade() else { return };
            let mut this = hub.borrow_mut();
            let named = this.settings.apply_entries(&entries);
            let added = this.settings.apply_declared(&declared);
            this.entries = Rc::new(entries);
            if named || added {
                this.settings_did_change(&hub);
                schedule_flush(&hub, &mut this);
            }
        });
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    pub fn set_lock_screen_notifications(hub: &HubRef, enabled: bool) {
        let mut this = hub.borrow_mut();
        if this.settings.lock_screen_notifications == enabled {
            return;
        }
        this.settings.lock_screen_notifications = enabled;
        this.shell_settings_changed = true;
        this.settings_did_change(hub);
        schedule_flush(hub, &mut this);
    }

    /// For notifications sent from now on (those in the list stay)
    pub fn set_app_enabled(hub: &HubRef, key: &str, enabled: bool) -> Result<(), OpError> {
        let mut this = hub.borrow_mut();
        match this.settings.set_enabled(key, enabled) {
            None => Err(OpError::new(ErrorCode::NotFound, format!("no application \"{key}\""))),
            Some(changed) => {
                if changed {
                    this.settings_did_change(hub);
                    schedule_flush(hub, &mut this);
                }
                Ok(())
            }
        }
    }

    pub fn add_settings_listener(hub: &HubRef, client: settings_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.settings_changed_request();
        rpc::write_settings(request.get().init_settings(), &this.settings, &this.store.dnd, now_ms());
        deliver_settings(hub, id, request.send().promise);
        this.settings_listeners.push((id, client));
        id
    }

    pub fn remove_settings_listener(&mut self, id: u64) {
        self.settings_listeners.retain(|(other, _)| *other != id);
    }

    /// Writes the settings now, if they wait to be written (the end of the service)
    pub fn save_settings_now(&mut self) {
        if let (true, Some(path)) = (self.save_scheduled, &self.settings_path) {
            self.save_scheduled = false;
            if let Err(error) = Settings::save(&self.settings.to_json(), path) {
                eprintln!("maia-notifications-service: {}: {error}", path.display());
            }
        }
    }

    /// The settings changed: to their listeners with the next batch, to the disk a moment later
    /// (many changes in a row are one write)
    fn settings_did_change(&mut self, hub: &HubRef) {
        self.settings_changed = true;
        if self.save_scheduled || self.settings_path.is_none() {
            return;
        }
        self.save_scheduled = true;
        let weak = Rc::downgrade(hub);
        tokio::task::spawn_local(async move {
            tokio::time::sleep(SETTINGS_SAVE_DELAY).await;
            let Some(hub) = weak.upgrade() else { return };
            let (text, path) = {
                let mut this = hub.borrow_mut();
                if !this.save_scheduled {
                    return;
                }
                this.save_scheduled = false;
                let Some(path) = this.settings_path.clone() else { return };
                (this.settings.to_json(), path)
            };
            let written = tokio::task::spawn_blocking(move || Settings::save(&text, &path).map_err(|e| format!("{}: {e}", path.display()))).await;
            if let Ok(Err(error)) = written {
                eprintln!("maia-notifications-service: {error}");
            }
        });
    }

    // --- Listeners ---

    pub fn add_listener(hub: &HubRef, client: center_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        rpc::write_snapshot(request.get().init_snapshot(), &this.store, &this.jobs, &this.settings, now_ms());
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    pub fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }

    // --- Inside ---

    fn mark_changed(&mut self, id: u32) {
        self.changed.insert(id);
    }

    fn send_out(&self, outgoing: Outgoing) {
        if let Some(out) = &self.dbus_out {
            let _ = out.send(outgoing);
        }
    }

    /// A job became visible: to the shells now
    fn job_shown(&mut self, id: u32) {
        self.job_throttle.added(&id.to_string(), Instant::now());
        self.jobs_changed.insert(id);
    }

    /// A visible job changed: to the shells at most every JOB_INTERVAL
    fn job_changed(&mut self, id: u32) {
        if self.job_throttle.changed(&id.to_string(), Instant::now()) {
            self.jobs_changed.insert(id);
        }
    }

    /// A job ended and stays: to the shells now, with nothing older waiting
    fn job_ended(&mut self, id: u32) {
        self.job_throttle.removed(&id.to_string());
        self.jobs_changed.insert(id);
    }

    fn job_removed(&mut self, id: u32) {
        self.job_throttle.removed(&id.to_string());
        self.jobs_changed.remove(&id);
        self.jobs_removed.push(id);
    }

    fn job_end(&mut self, id: u32, ended: Ended) {
        match ended {
            Ended::NotFound => return,
            Ended::Removed { was_visible } => {
                if was_visible {
                    self.job_removed(id);
                }
            }
            Ended::Kept { .. } => self.job_ended(id),
        }
        // Over for its program: a Maia sender's listener is let go, a D-Bus job's objects go
        if self.job_listeners.remove(&id).is_none() {
            self.send_out(Outgoing::JobGone(id));
        }
        for dropped in self.jobs.trim() {
            self.job_removed(dropped);
        }
        self.check_job_urls();
    }

    /// Passes the user's request to the job's program: its JobListener, or D-Bus
    fn ask_job(&self, id: u32, kind: crate::dbus_jobs::JobRequestKind) {
        use crate::dbus_jobs::JobRequestKind;
        let Some(listener) = self.job_listeners.get(&id) else {
            self.send_out(Outgoing::JobRequest { id, kind });
            return;
        };
        // In the background: a sender that does not answer holds nothing up
        let sent = match kind {
            JobRequestKind::Cancel => listener.cancel_requested_request().send().promise.map(|r| r.map(|_| ())).boxed_local(),
            JobRequestKind::Suspend => listener.suspend_requested_request().send().promise.map(|r| r.map(|_| ())).boxed_local(),
            JobRequestKind::Resume => listener.resume_requested_request().send().promise.map(|r| r.map(|_| ())).boxed_local(),
        };
        tokio::task::spawn_local(async move {
            let _ = sent.await;
        });
    }

    /// Tells the bus where the running jobs write to, when that changed
    fn check_job_urls(&mut self) {
        let urls = self.jobs.running_urls();
        if urls != self.job_urls {
            self.job_urls = urls.clone();
            self.send_out(Outgoing::JobUrls(urls));
        }
    }

    fn mark_removed(&mut self, id: u32) {
        self.changed.remove(&id);
        self.removed.push(id);
    }

    /// Removes a notification and tells its sender why; false when there is none
    fn close(&mut self, id: u32, reason: CloseReason) -> bool {
        let Some(entry) = self.store.remove(id) else { return false };
        if entry.ready {
            self.mark_removed(id);
        }
        if let Some(file) = entry.image_file {
            discard(file);
        }
        self.tell(&entry.origin, id, SenderEvent::Closed(reason));
        true
    }

    fn tell(&self, origin: &Origin, id: u32, event: SenderEvent) {
        match origin {
            Origin::Nobody => {}
            Origin::DBus(destination) => {
                if let Some(out) = &self.dbus_out {
                    let _ = out.send(Outgoing::Signal { destination: destination.clone(), id, event });
                }
            }
            Origin::Maia(listener) => {
                // Calls on one capability arrive in the order they are made; a sender that is gone
                // does not matter
                match event {
                    SenderEvent::ActionInvoked { key, token } => {
                        let mut request = listener.action_invoked_request();
                        request.get().set_key(&key);
                        request.get().set_activation_token(&token);
                        let promise = request.send().promise;
                        tokio::task::spawn_local(async move {
                            let _ = promise.await;
                        });
                    }
                    SenderEvent::Replied { text, token } => {
                        let mut request = listener.replied_request();
                        request.get().set_text(&text);
                        request.get().set_activation_token(&token);
                        let promise = request.send().promise;
                        tokio::task::spawn_local(async move {
                            let _ = promise.await;
                        });
                    }
                    SenderEvent::Closed(reason) => {
                        let mut request = listener.closed_request();
                        request.get().set_reason(rpc::write_reason(reason));
                        let promise = request.send().promise;
                        tokio::task::spawn_local(async move {
                            let _ = promise.await;
                        });
                    }
                }
            }
        }
    }

    fn dnd_did_change(&mut self) {
        self.dnd_changed = true;
        let active = self.store.dnd.active_at(now_ms());
        if self.inhibited.swap(active, Ordering::SeqCst) != active {
            if let Some(out) = &self.dbus_out {
                let _ = out.send(Outgoing::InhibitedChanged);
            }
        }
    }

    /// Sends the collected batch to every shell
    fn flush(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        this.flush_scheduled = false;
        this.last_flush = Some(Instant::now());
        let changed: Vec<u32> = std::mem::take(&mut this.changed).into_iter().collect();
        let removed = std::mem::take(&mut this.removed);
        let dnd = std::mem::take(&mut this.dnd_changed);
        let settings_changed = std::mem::take(&mut this.settings_changed) || dnd;
        let shell_settings = std::mem::take(&mut this.shell_settings_changed);
        for key in this.job_throttle.take_due(Instant::now()) {
            if let Ok(id) = key.parse::<u32>() {
                this.jobs_changed.insert(id);
            }
        }
        let job_ids: Vec<u32> = std::mem::take(&mut this.jobs_changed).into_iter().collect();
        let jobs_removed = std::mem::take(&mut this.jobs_removed);
        let jobs: Vec<_> = job_ids.iter().filter_map(|id| this.jobs.get(*id)).filter(|e| e.visible).map(|e| &e.job).collect();
        let notifications: Vec<_> = changed
            .iter()
            .filter_map(|id| this.store.get(*id))
            .filter(|e| e.ready)
            .map(|e| &e.notification)
            .collect();
        let now = now_ms();
        for (listener_id, listener) in &this.listeners {
            if !notifications.is_empty() || !removed.is_empty() {
                let mut request = listener.changes_request();
                {
                    let mut list = request.get().init_changed(notifications.len() as u32);
                    for (i, n) in notifications.iter().enumerate() {
                        rpc::write_notification(list.reborrow().get(i as u32), n);
                    }
                }
                {
                    let mut list = request.get().init_removed(removed.len() as u32);
                    for (i, id) in removed.iter().enumerate() {
                        list.set(i as u32, *id);
                    }
                }
                deliver(hub, *listener_id, request.send().promise);
            }
            if dnd {
                let mut request = listener.do_not_disturb_changed_request();
                rpc::write_do_not_disturb(request.get().init_do_not_disturb(), &this.store.dnd, now);
                deliver(hub, *listener_id, request.send().promise);
            }
            if shell_settings {
                let mut request = listener.shell_settings_changed_request();
                rpc::write_shell_settings(request.get().init_settings(), &this.settings);
                deliver(hub, *listener_id, request.send().promise);
            }
            if !jobs.is_empty() || !jobs_removed.is_empty() {
                let mut request = listener.jobs_changed_request();
                {
                    let mut list = request.get().init_changed(jobs.len() as u32);
                    for (i, job) in jobs.iter().enumerate() {
                        rpc::write_job(list.reborrow().get(i as u32), job);
                    }
                }
                {
                    let mut list = request.get().init_removed(jobs_removed.len() as u32);
                    for (i, id) in jobs_removed.iter().enumerate() {
                        list.set(i as u32, *id);
                    }
                }
                deliver(hub, *listener_id, request.send().promise);
            }
        }
        if settings_changed {
            for (listener_id, listener) in &this.settings_listeners {
                let mut request = listener.settings_changed_request();
                rpc::write_settings(request.get().init_settings(), &this.settings, &this.store.dnd, now);
                deliver_settings(hub, *listener_id, request.send().promise);
            }
        }
        // Changes of jobs that wait for their interval
        schedule_flush(hub, &mut this);
    }
}

/// The batch goes out at the next frame
fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled {
        return;
    }
    let pending = !this.changed.is_empty()
        || !this.removed.is_empty()
        || this.dnd_changed
        || this.settings_changed
        || this.shell_settings_changed
        || !this.jobs_changed.is_empty()
        || !this.jobs_removed.is_empty();
    let frame = this.last_flush.map(|last| last + FRAME).unwrap_or_else(Instant::now);
    let at = if pending {
        frame
    } else {
        // Only a job's change waits for its interval
        match this.job_throttle.next_deadline() {
            Some(deadline) => deadline.max(frame),
            None => return,
        }
    };
    this.flush_scheduled = true;
    let weak: Weak<RefCell<Hub>> = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        // Also when it is due already: everything that arrives in this turn of the loop joins
        tokio::time::sleep_until(tokio::time::Instant::from_std(at.max(Instant::now()))).await;
        if let Some(hub) = weak.upgrade() {
            Hub::flush(&hub);
        }
    });
}

/// Writes the pixels in the background; the notification is shown when they are written
fn write_image(hub: &HubRef, dir: Option<PathBuf>, id: u32, generation: u64, pixels: crate::model::Pixels) {
    let weak = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        let result = match dir {
            Some(dir) => tokio::task::spawn_blocking(move || image::write_png(&dir, id, generation, &pixels))
                .await
                .unwrap_or_else(|error| Err(error.to_string())),
            None => Err("no directory for images".to_string()),
        };
        let Some(hub) = weak.upgrade() else {
            if let Ok((file, _)) = result {
                discard(file);
            }
            return;
        };
        let mut this = hub.borrow_mut();
        match result {
            Ok((file, url)) => {
                if this.store.set_image(id, generation, url, file.clone()) {
                    this.mark_changed(id);
                } else {
                    // Replaced or closed meanwhile
                    discard(file);
                }
            }
            Err(error) => {
                eprintln!("maia-notifications-service: the image of notification {id}: {error}");
                if this.store.image_failed(id, generation) {
                    this.mark_changed(id);
                }
            }
        }
        schedule_flush(&hub, &mut this);
    });
}

/// Removes an image file in the background
fn discard(file: PathBuf) {
    tokio::task::spawn_blocking(move || {
        let _ = std::fs::remove_file(file);
    });
}

/// Runs the call in the background; when it fails, the listener is gone
/// Whether a listener's failed call means it is gone. A listener built on an older contract answers
/// a newer call with "unimplemented": it stays, and gets the calls it knows.
fn gone(error: &capnp::Error) -> bool {
    error.kind != capnp::ErrorKind::Unimplemented
}

/// A settings listener that fails is dropped
fn deliver_settings<T: 'static>(hub: &HubRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        if promise.await.is_err_and(|e| gone(&e)) {
            if let Some(hub) = hub.upgrade() {
                hub.borrow_mut().remove_settings_listener(id);
            }
        }
    });
}

fn deliver<T: 'static>(hub: &HubRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        if promise.await.is_err_and(|e| gone(&e)) {
            if let Some(hub) = hub.upgrade() {
                hub.borrow_mut().remove_listener(id);
            }
        }
    });
}
