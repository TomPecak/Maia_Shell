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
use std::collections::BTreeSet;
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use tokio::sync::mpsc;

use crate::image;
use crate::model::{CloseReason, Expired, Inhibitor, Request, Store, now_ms};
use crate::notifications_capnp::{center_listener, notifier_listener};
use crate::rpc;

/// The shortest time between two batches to the shells: one frame
pub const FRAME: Duration = Duration::from_millis(16);

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
}

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
        }))
    }

    pub fn store(&self) -> &Store<Origin> {
        &self.store
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

    /// A D-Bus client left the bus: its inhibitions end
    pub fn owner_gone(hub: &HubRef, name: &str) {
        let mut this = hub.borrow_mut();
        if this.store.owner_gone(name) {
            this.dnd_did_change();
            schedule_flush(hub, &mut this);
        }
    }

    // --- Listeners ---

    pub fn add_listener(hub: &HubRef, client: center_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        rpc::write_snapshot(request.get().init_snapshot(), &this.store, now_ms());
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
        }
    }
}

/// The batch goes out at the next frame
fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled || (this.changed.is_empty() && this.removed.is_empty() && !this.dnd_changed) {
        return;
    }
    this.flush_scheduled = true;
    let at = this.last_flush.map(|last| last + FRAME).unwrap_or_else(Instant::now);
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
fn deliver<T: 'static>(hub: &HubRef, id: u64, promise: capnp::capability::Promise<T, capnp::Error>) {
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        if promise.await.is_err() {
            if let Some(hub) = hub.upgrade() {
                hub.borrow_mut().remove_listener(id);
            }
        }
    });
}
