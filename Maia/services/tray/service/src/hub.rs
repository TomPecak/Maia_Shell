//! The hub: the items of the session, the shells that watch them and the menus they have open.
//!
//! ```text
//!   watcher (watcher.rs) ──register──┐                          ┌──► TrayListener (shells): snapshot,
//!   NameOwnerChanged ───────gone─────┼──► Hub: items, rules  ───┤    then one batch per frame
//!   item tasks (sni.rs) ──read───────┘                          ├──► open menus: closed() when
//!                                                               │    their item goes
//!   TrayHost (rpc.rs) ── clicks ──► the application (D-Bus)     └──► watcher signals (registered,
//!                                                                    unregistered)
//! ```
//!
//! An item is known from its registration, but sent to the shells only once its properties are
//! read (an item that does not answer is never shown). Changes go out in batches: a change marks
//! the item, the batch goes out at the next frame (16 ms after the previous one at the earliest).
//!
//! Everything runs in the service's one thread and nothing here waits: an item is read by its own
//! task, a click is sent in the background, calls to listeners go out in the background, in order.

use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::rc::{Rc, Weak};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tokio::sync::mpsc;

use crate::desktop::{Apps, Process};
use crate::image::{ImageRef, ImageStoreRef};
use crate::model::Item;
use crate::rpc;
use crate::tray_capnp::{menu_listener, tray_listener};

/// The shortest time between two batches to the shells: one frame
pub const FRAME: Duration = Duration::from_millis(16);

/// How long a call to an application may take before it counts as not answering
pub const CALL_TIMEOUT: Duration = Duration::from_secs(5);

/// Where an item lives on the bus
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Address {
    /// What the application registered, as the watcher lists it ("org.kde.StatusNotifierItem-12-1/
    /// StatusNotifierItem", ":1.40/org/ayatana/NotificationItem/x")
    pub service: String,
    /// The bus name to call (well-known or unique)
    pub name: String,
    pub path: String,
}

impl Address {
    /// From RegisterStatusNotifierItem: a bus name (the object is /StatusNotifierItem), an object
    /// path of the sender, or both as "name/path". None when it is neither.
    pub fn from_registration(sender: &str, service: &str) -> Option<Address> {
        let service = service.trim();
        let (name, path) = if service.starts_with('/') {
            (sender.to_string(), service.to_string())
        } else if let Some(at) = service.find('/') {
            (service[..at].to_string(), service[at..].to_string())
        } else {
            (service.to_string(), "/StatusNotifierItem".to_string())
        };
        zbus::names::BusName::try_from(name.as_str()).ok()?;
        zbus::zvariant::ObjectPath::try_from(path.as_str()).ok()?;
        Some(Address { service: format!("{name}{path}"), name, path })
    }
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

    pub fn not_found(id: u32) -> OpError {
        OpError::new(ErrorCode::NotFound, format!("no item {id}"))
    }
}

/// What the watcher tells the bus (watcher.rs sends them in this order)
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WatcherSignal {
    ItemRegistered(String),
    ItemUnregistered(String),
    HostRegistered,
    HostUnregistered,
}

/// What the watcher's D-Bus properties read (from zbus's threads)
#[derive(Debug, Default)]
pub struct WatcherState {
    pub items: Vec<String>,
    pub hosts: Vec<String>,
}

/// What the item task of an item has read: the item for the shells and what it keeps alive
pub struct ItemRead {
    pub item: Item,
    pub images: Vec<ImageRef>,
    pub menu_path: String,
    pub sni_id: String,
}

pub struct Entry {
    pub address: Address,
    /// The unique name of the application, once known (the item task asks the bus)
    pub owner: String,
    pub process: Process,
    /// None until the item is read
    pub item: Option<Item>,
    pub menu_path: String,
    sni_id: String,
    images: Vec<ImageRef>,
    task: Option<tokio::task::JoinHandle<()>>,
}

impl Drop for Entry {
    fn drop(&mut self) {
        if let Some(task) = self.task.take() {
            task.abort();
        }
    }
}

pub struct Hub {
    items: BTreeMap<u32, Entry>,
    next_id: u32,
    listeners: Vec<(u64, tray_listener::Client)>,
    next_listener: u64,
    /// Open menus: (item, menu, listener), told when their item goes
    menus: Vec<(u32, u64, menu_listener::Client)>,
    next_menu: u64,
    // The batch being collected
    changed: BTreeSet<u32>,
    removed: Vec<u32>,
    flush_scheduled: bool,
    last_flush: Option<Instant>,
    images: ImageStoreRef,
    apps: Rc<Apps>,
    connection: Option<zbus::Connection>,
    watcher_state: Arc<Mutex<WatcherState>>,
    watcher_out: Option<mpsc::UnboundedSender<WatcherSignal>>,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    /// connection: the session bus the items are on (None: tests without D-Bus)
    pub fn new(images: ImageStoreRef, connection: Option<zbus::Connection>) -> HubRef {
        Rc::new(RefCell::new(Hub {
            items: BTreeMap::new(),
            next_id: 1,
            listeners: Vec::new(),
            next_listener: 0,
            menus: Vec::new(),
            next_menu: 0,
            changed: BTreeSet::new(),
            removed: Vec::new(),
            flush_scheduled: false,
            last_flush: None,
            images,
            apps: Rc::new(Apps::default()),
            connection,
            watcher_state: Arc::new(Mutex::new(WatcherState::default())),
            watcher_out: None,
        }))
    }

    pub fn connection(&self) -> Option<&zbus::Connection> {
        self.connection.as_ref()
    }

    pub fn images(&self) -> ImageStoreRef {
        self.images.clone()
    }

    pub fn apps(&self) -> Rc<Apps> {
        self.apps.clone()
    }

    pub fn watcher_state(&self) -> Arc<Mutex<WatcherState>> {
        self.watcher_state.clone()
    }

    pub fn set_watcher_out(&mut self, out: mpsc::UnboundedSender<WatcherSignal>) {
        self.watcher_out = Some(out);
    }

    pub fn get(&self, id: u32) -> Option<&Entry> {
        self.items.get(&id)
    }

    /// The items the shells see, in the order of ids
    pub fn shown(&self) -> Vec<&Item> {
        self.items.values().filter_map(|e| e.item.as_ref()).collect()
    }

    /// The unique name behind an item's address, once its task knows it
    pub fn get_owner_of(&self, address: &Address) -> Option<String> {
        self.items.values().find(|e| e.address == *address).map(|e| e.owner.clone()).filter(|o| !o.is_empty())
    }

    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    pub fn menu_count(&self) -> usize {
        self.menus.len()
    }

    // --- Items ---

    /// A registered item; None when it is registered already. Its task reads it in the background.
    pub fn add_item(hub: &HubRef, address: Address) -> Option<u32> {
        let mut this = hub.borrow_mut();
        if this.items.values().any(|e| e.address.service == address.service) {
            return None;
        }
        let id = this.next_id;
        this.next_id += 1;
        let service = address.service.clone();
        let task = this.connection.clone().map(|connection| {
            tokio::task::spawn_local(crate::sni::track(Rc::downgrade(hub), id, address.clone(), connection))
        });
        this.items.insert(
            id,
            Entry {
                address,
                owner: String::new(),
                process: Process::default(),
                item: None,
                menu_path: String::new(),
                sni_id: String::new(),
                images: Vec::new(),
                task,
            },
        );
        this.watcher_state.lock().unwrap().items.push(service.clone());
        this.signal(WatcherSignal::ItemRegistered(service));
        Some(id)
    }

    /// The item task knows who owns the item
    pub fn set_owner(hub: &HubRef, id: u32, owner: String, process: Process) {
        let mut this = hub.borrow_mut();
        if let Some(entry) = this.items.get_mut(&id) {
            entry.owner = owner;
            entry.process = process;
        }
    }

    /// The item task has read the item (the first time, or after a change)
    pub fn item_read(hub: &HubRef, id: u32, read: ItemRead) {
        let mut this = hub.borrow_mut();
        let apps = this.apps.clone();
        let Some(entry) = this.items.get_mut(&id) else { return };
        let mut item = read.item;
        item.id = id;
        apply_app(&mut item, &read.sni_id, &entry.process, &apps);
        entry.menu_path = read.menu_path;
        entry.sni_id = read.sni_id;
        // The new images are taken before the old ones are let go: an unchanged one stays
        entry.images = read.images;
        if entry.item.as_ref() != Some(&item) {
            entry.item = Some(item);
            this.changed.insert(id);
            schedule_flush(hub, &mut this);
        }
    }

    /// Gone, or never readable
    pub fn remove_item(hub: &HubRef, id: u32) {
        let mut this = hub.borrow_mut();
        let Some(entry) = this.items.remove(&id) else { return };
        if entry.item.is_some() {
            this.changed.remove(&id);
            this.removed.push(id);
        }
        let service = entry.address.service.clone();
        this.watcher_state.lock().unwrap().items.retain(|s| *s != service);
        this.signal(WatcherSignal::ItemUnregistered(service));
        // Its open menus close
        let (closing, open): (Vec<_>, Vec<_>) = std::mem::take(&mut this.menus).into_iter().partition(|(item, _, _)| *item == id);
        this.menus = open;
        for (_, _, listener) in closing {
            let promise = listener.closed_request().send().promise;
            tokio::task::spawn_local(async move {
                let _ = promise.await;
            });
        }
        drop(entry);
        schedule_flush(hub, &mut this);
    }

    /// The item an application registered as `service` is gone (the foreign watcher said so)
    pub fn remove_service(hub: &HubRef, service: &str) {
        let id = hub.borrow().items.iter().find(|(_, e)| e.address.service == service).map(|(id, _)| *id);
        if let Some(id) = id {
            Hub::remove_item(hub, id);
        }
    }

    /// A name left the bus: the items it owned go, a host that had it is gone
    pub fn name_gone(hub: &HubRef, name: &str) {
        let gone: Vec<u32> = hub
            .borrow()
            .items
            .iter()
            .filter(|(_, e)| e.address.name == name || e.owner == name)
            .map(|(id, _)| *id)
            .collect();
        for id in gone {
            Hub::remove_item(hub, id);
        }
        let this = hub.borrow();
        let was_host = {
            let mut state = this.watcher_state.lock().unwrap();
            let before = state.hosts.len();
            state.hosts.retain(|h| h != name);
            state.hosts.len() != before
        };
        if was_host {
            this.signal(WatcherSignal::HostUnregistered);
        }
    }

    /// Another host registered with our watcher (we are one, always)
    pub fn add_host(hub: &HubRef, name: String) {
        let this = hub.borrow();
        let added = {
            let mut state = this.watcher_state.lock().unwrap();
            let new = !state.hosts.contains(&name);
            if new {
                state.hosts.push(name);
            }
            new
        };
        if added {
            this.signal(WatcherSignal::HostRegistered);
        }
    }

    /// The desktop entries are read: the items get their applications
    pub fn set_apps(hub: &HubRef, apps: Apps) {
        let mut this = hub.borrow_mut();
        this.apps = Rc::new(apps);
        let apps = this.apps.clone();
        let mut changed = Vec::new();
        for (id, entry) in this.items.iter_mut() {
            let Some(item) = entry.item.as_mut() else { continue };
            let before = item.clone();
            apply_app(item, &entry.sni_id, &entry.process, &apps);
            if *item != before {
                changed.push(*id);
            }
        }
        this.changed.extend(changed);
        schedule_flush(hub, &mut this);
    }

    // --- Clicks (sent in the background, never waited for) ---

    fn target(&self, id: u32) -> Result<(zbus::Connection, Address), OpError> {
        let entry = self.items.get(&id).filter(|e| e.item.is_some()).ok_or_else(|| OpError::not_found(id))?;
        let connection = self.connection.clone().ok_or_else(|| OpError::new(ErrorCode::Unavailable, "no D-Bus"))?;
        Ok((connection, entry.address.clone()))
    }

    pub fn activate(hub: &HubRef, id: u32, x: i32, y: i32, token: &str, secondary: bool) -> Result<(), OpError> {
        let (connection, address) = hub.borrow().target(id)?;
        let token = token.to_string();
        tokio::task::spawn_local(async move {
            if !token.is_empty() {
                crate::sni::provide_token(&connection, &address, &token).await;
            }
            let method = if secondary { "SecondaryActivate" } else { "Activate" };
            crate::sni::call(&connection, &address, method, &(x, y)).await;
        });
        Ok(())
    }

    pub fn context_menu(hub: &HubRef, id: u32, x: i32, y: i32) -> Result<(), OpError> {
        let (connection, address) = hub.borrow().target(id)?;
        tokio::task::spawn_local(async move {
            crate::sni::call(&connection, &address, "ContextMenu", &(x, y)).await;
        });
        Ok(())
    }

    pub fn scroll(hub: &HubRef, id: u32, delta: i32, horizontal: bool) -> Result<(), OpError> {
        let (connection, address) = hub.borrow().target(id)?;
        let orientation = if horizontal { "horizontal" } else { "vertical" };
        tokio::task::spawn_local(async move {
            crate::sni::call(&connection, &address, "Scroll", &(delta, orientation)).await;
        });
        Ok(())
    }

    /// Where an item's menu is: the connection, the item and the menu's path
    pub fn menu_target(&self, id: u32) -> Result<(zbus::Connection, Address, String), OpError> {
        let (connection, address) = self.target(id)?;
        let path = self.items[&id].menu_path.clone();
        if path.is_empty() {
            return Err(OpError::new(ErrorCode::InvalidArgument, format!("item {id} has no menu")));
        }
        Ok((connection, address, path))
    }

    /// An open menu of item `id`; told closed() when the item goes. Returns its number.
    pub fn add_menu(&mut self, id: u32, listener: menu_listener::Client) -> u64 {
        self.next_menu += 1;
        self.menus.push((id, self.next_menu, listener));
        self.next_menu
    }

    pub fn remove_menu(&mut self, menu: u64) {
        self.menus.retain(|(_, other, _)| *other != menu);
    }

    // --- Listeners ---

    pub fn add_listener(hub: &HubRef, client: tray_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        {
            let shown = this.shown();
            let mut list = request.get().init_items(shown.len() as u32);
            for (i, item) in shown.iter().enumerate() {
                rpc::write_item(list.reborrow().get(i as u32), item);
            }
        }
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    pub fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }

    // --- Inside ---

    fn signal(&self, signal: WatcherSignal) {
        if let Some(out) = &self.watcher_out {
            let _ = out.send(signal);
        }
    }

    /// Sends the collected batch to every shell
    fn flush(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        this.flush_scheduled = false;
        this.last_flush = Some(Instant::now());
        let changed: Vec<u32> = std::mem::take(&mut this.changed).into_iter().collect();
        let removed = std::mem::take(&mut this.removed);
        let items: Vec<&Item> = changed.iter().filter_map(|id| this.items.get(id)).filter_map(|e| e.item.as_ref()).collect();
        if items.is_empty() && removed.is_empty() {
            return;
        }
        for (listener_id, listener) in &this.listeners {
            let mut request = listener.changes_request();
            {
                let mut list = request.get().init_changed(items.len() as u32);
                for (i, item) in items.iter().enumerate() {
                    rpc::write_item(list.reborrow().get(i as u32), item);
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
    }
}

/// The application of an item, and its key, from the desktop entries
fn apply_app(item: &mut Item, sni_id: &str, process: &Process, apps: &Apps) {
    match apps.find(sni_id, process) {
        Some(entry) => {
            item.desktop_entry = entry.id.clone();
            item.app_name = if entry.name.is_empty() { item.title.clone() } else { entry.name.clone() };
            item.app_icon = if entry.icon.starts_with('/') { crate::image::url_from_path(&entry.icon) } else { entry.icon.clone() };
        }
        None => {
            item.desktop_entry.clear();
            item.app_name = item.title.clone();
            item.app_icon.clear();
        }
    }
    item.key = match (item.desktop_entry.as_str(), sni_id) {
        ("", "") => item.title.clone(),
        ("", id) => id.to_string(),
        (entry, id) if id.is_empty() || id == entry => entry.to_string(),
        (entry, id) => format!("{entry}/{id}"),
    };
}

/// The batch goes out at the next frame
fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled || (this.changed.is_empty() && this.removed.is_empty()) {
        return;
    }
    let at = this.last_flush.map(|last| last + FRAME).unwrap_or_else(Instant::now);
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

/// Whether a listener's failed call means it is gone. A listener built on an older contract answers
/// a newer call with "unimplemented": it stays, and gets the calls it knows.
fn gone(error: &capnp::Error) -> bool {
    error.kind != capnp::ErrorKind::Unimplemented
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desktop::Entry as DesktopEntry;

    #[test]
    fn registrations_in_their_three_forms() {
        let by_name = Address::from_registration(":1.7", "org.kde.StatusNotifierItem-12-1").unwrap();
        assert_eq!(by_name.name, "org.kde.StatusNotifierItem-12-1");
        assert_eq!(by_name.path, "/StatusNotifierItem");
        assert_eq!(by_name.service, "org.kde.StatusNotifierItem-12-1/StatusNotifierItem");
        let by_path = Address::from_registration(":1.7", "/org/ayatana/NotificationItem/app").unwrap();
        assert_eq!((by_path.name.as_str(), by_path.path.as_str()), (":1.7", "/org/ayatana/NotificationItem/app"));
        assert_eq!(by_path.service, ":1.7/org/ayatana/NotificationItem/app");
        let both = Address::from_registration(":1.7", ":1.9/StatusNotifierItem").unwrap();
        assert_eq!((both.name.as_str(), both.path.as_str()), (":1.9", "/StatusNotifierItem"));
        assert!(Address::from_registration(":1.7", "not a name!").is_none());
        assert!(Address::from_registration(":1.7", "/bad//path").is_none());
    }

    #[test]
    fn keys_stay_across_restarts() {
        let apps = Apps::from_entries(vec![DesktopEntry {
            id: "signal-desktop".into(),
            name: "Signal".into(),
            icon: "signal-desktop".into(),
            wm_class: String::new(),
            program: "signal-desktop".into(),
        }]);
        let mut item = Item { title: "Signal".into(), ..Item::default() };
        let process = Process { flatpak_id: String::new(), program: "signal-desktop".into() };
        apply_app(&mut item, "chrome_status_icon_1", &process, &apps);
        assert_eq!(item.key, "signal-desktop/chrome_status_icon_1");
        assert_eq!((item.desktop_entry.as_str(), item.app_name.as_str()), ("signal-desktop", "Signal"));
        let mut unknown = Item { title: "Thing".into(), ..Item::default() };
        apply_app(&mut unknown, "thing", &Process::default(), &apps);
        assert_eq!((unknown.key.as_str(), unknown.app_name.as_str()), ("thing", "Thing"));
        let mut nameless = Item { title: "T".into(), ..Item::default() };
        apply_app(&mut nameless, "", &Process::default(), &apps);
        assert_eq!(nameless.key, "T");
    }
}
