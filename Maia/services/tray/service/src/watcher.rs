//! The watcher: org.kde.StatusNotifierWatcher at /StatusNotifierWatcher on the session bus, where
//! applications register their items, and the host side of it.
//!
//! The service is the session's watcher and its only host: it says a host is there
//! (IsStatusNotifierHostRegistered, which Qt and libappindicator check before they show an item at
//! all), and reads every registered item itself.
//!
//! When another program keeps the watcher's name (Plasma's kded module in a session that runs it),
//! the service waits in the name's queue and is a host of that watcher meanwhile: it registers
//! with it, takes its items and follows its signals. When the other watcher ends, the bus gives the
//! name to the service, and applications register again with it (they watch the name).
//!
//! zbus calls the methods from its own tasks, which must be Send; the hub is not. So a method only
//! hands a `WatcherCall` to the hub's task (`run_calls`); the properties are read from a shared
//! state the hub keeps; signals go out in the hub's order (`run_signals`).

use std::sync::{Arc, Mutex};

use futures::StreamExt;
use tokio::sync::mpsc;
use zbus::fdo::RequestNameReply;
use zbus::message::Header;
use zbus::object_server::SignalEmitter;

use crate::hub::{Address, Hub, HubRef, WatcherSignal, WatcherState};

pub const NAME: &str = "org.kde.StatusNotifierWatcher";
pub const PATH: &str = "/StatusNotifierWatcher";
pub const PROTOCOL_VERSION: i32 = 0;

/// A call of a D-Bus client, for the hub's task
#[derive(Debug)]
pub enum WatcherCall {
    RegisterItem(Address),
    RegisterHost(String),
    NameGone(String),
}

pub struct Watcher {
    calls: mpsc::UnboundedSender<WatcherCall>,
    state: Arc<Mutex<WatcherState>>,
}

fn sender_of(header: &Header<'_>) -> String {
    header.sender().map(|s| s.to_string()).unwrap_or_default()
}

fn gone() -> zbus::fdo::Error {
    zbus::fdo::Error::Failed("the tray service is ending".into())
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(&self, #[zbus(header)] header: Header<'_>, service: String) -> zbus::fdo::Result<()> {
        let sender = sender_of(&header);
        let address = Address::from_registration(&sender, &service)
            .ok_or_else(|| zbus::fdo::Error::InvalidArgs(format!("\"{service}\" is neither a bus name nor an object path")))?;
        self.calls.send(WatcherCall::RegisterItem(address)).map_err(|_| gone())
    }

    async fn register_status_notifier_host(&self, #[zbus(header)] header: Header<'_>, service: String) -> zbus::fdo::Result<()> {
        let name = if service.trim().is_empty() { sender_of(&header) } else { service.trim().to_string() };
        self.calls.send(WatcherCall::RegisterHost(name)).map_err(|_| gone())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.state.lock().unwrap().items.clone()
    }

    /// We are a host, always
    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        PROTOCOL_VERSION
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(emitter: &SignalEmitter<'_>, service: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(emitter: &SignalEmitter<'_>, service: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_unregistered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// Our name as a host (org.kde.StatusNotifierHost-<pid>)
pub fn host_name() -> String {
    format!("org.kde.StatusNotifierHost-{}", std::process::id())
}

/// Serves the watcher on `connection` and connects it to the hub, then takes the watcher's name (or
/// waits for it, a host of the other watcher meanwhile). Everything runs in the background of the
/// current LocalSet. Returns whether the name is ours now.
pub async fn serve(connection: &zbus::Connection, hub: &HubRef) -> zbus::Result<bool> {
    let (calls, call_receiver) = mpsc::unbounded_channel();
    let (out, out_receiver) = mpsc::unbounded_channel();
    let state = hub.borrow().watcher_state();
    connection.object_server().at(PATH, Watcher { calls: calls.clone(), state }).await?;
    hub.borrow_mut().set_watcher_out(out);
    tokio::task::spawn_local(run_calls(hub.clone(), call_receiver));
    tokio::task::spawn_local(run_signals(connection.clone(), out_receiver));
    // Before the name is taken: an item that registers at once is followed from the start
    watch_owners(connection, calls).await?;

    let host = host_name();
    if let Err(error) = connection.request_name(host.as_str()).await {
        eprintln!("maia-tray-service: {host}: {error}");
    }
    // In the queue, without replacing: a watcher that runs is left alone (and zbus's default
    // flags would replace it)
    let reply = connection.request_name_with_flags(NAME, enumflags2::BitFlags::empty()).await?;
    let ours = matches!(reply, RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner);
    if !ours {
        eprintln!("maia-tray-service: another program is the watcher; a host of it until it ends");
        tokio::task::spawn_local(follow_other_watcher(connection.clone(), hub.clone()));
    }
    Ok(ours)
}

async fn run_calls(hub: HubRef, mut calls: mpsc::UnboundedReceiver<WatcherCall>) {
    while let Some(call) = calls.recv().await {
        match call {
            WatcherCall::RegisterItem(address) => {
                Hub::add_item(&hub, address);
            }
            WatcherCall::RegisterHost(name) => Hub::add_host(&hub, name),
            WatcherCall::NameGone(name) => Hub::name_gone(&hub, &name),
        }
    }
}

/// Sends the watcher's signals in the hub's order
async fn run_signals(connection: zbus::Connection, mut out: mpsc::UnboundedReceiver<WatcherSignal>) {
    let Ok(emitter) = SignalEmitter::new(&connection, PATH) else { return };
    while let Some(signal) = out.recv().await {
        let result = match signal {
            WatcherSignal::ItemRegistered(service) => Watcher::status_notifier_item_registered(&emitter, &service).await,
            WatcherSignal::ItemUnregistered(service) => Watcher::status_notifier_item_unregistered(&emitter, &service).await,
            WatcherSignal::HostRegistered => Watcher::status_notifier_host_registered(&emitter).await,
            WatcherSignal::HostUnregistered => Watcher::status_notifier_host_unregistered(&emitter).await,
        };
        if let Err(error) = result {
            eprintln!("maia-tray-service: D-Bus signal: {error}");
        }
    }
}

/// Names that leave the bus: their items and hosts go
async fn watch_owners(connection: &zbus::Connection, calls: mpsc::UnboundedSender<WatcherCall>) -> zbus::Result<()> {
    let proxy = zbus::fdo::DBusProxy::new(connection).await?;
    let mut changes = proxy.receive_name_owner_changed().await?;
    tokio::task::spawn_local(async move {
        while let Some(change) = changes.next().await {
            let Ok(args) = change.args() else { continue };
            // Gone, or another owner now (another process behind the same name: it registers anew)
            if args.old_owner().is_some() && calls.send(WatcherCall::NameGone(args.name().to_string())).is_err() {
                return;
            }
        }
    });
    Ok(())
}

#[zbus::proxy(interface = "org.kde.StatusNotifierWatcher", default_path = "/StatusNotifierWatcher", gen_blocking = false)]
trait OtherWatcher {
    fn register_status_notifier_host(&self, service: &str) -> zbus::Result<()>;
    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> zbus::Result<Vec<String>>;
    #[zbus(signal)]
    fn status_notifier_item_registered(&self, service: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    fn status_notifier_item_unregistered(&self, service: &str) -> zbus::Result<()>;
}

/// A host of another watcher: its items are ours to show, until the bus gives us its name
async fn follow_other_watcher(connection: zbus::Connection, hub: HubRef) {
    let Ok(dbus) = zbus::fdo::DBusProxy::new(&connection).await else { return };
    let Ok(mut acquired) = dbus.receive_name_acquired().await else { return };
    let Ok(other) = OtherWatcherProxy::builder(&connection)
        .destination(NAME)
        .and_then(|b| Ok(b.cache_properties(zbus::proxy::CacheProperties::No)))
        .map(|b| b.build())
    else {
        return;
    };
    let Ok(other) = other.await else { return };
    let (Ok(mut registered), Ok(mut unregistered)) =
        (other.receive_status_notifier_item_registered().await, other.receive_status_notifier_item_unregistered().await)
    else {
        return;
    };
    let add = |service: &str| {
        // The watcher lists "name/path", or a bare name with the usual path
        if let Some(address) = Address::from_registration("", service) {
            Hub::add_item(&hub, address);
        }
    };
    if let Err(error) = other.register_status_notifier_host(&host_name()).await {
        eprintln!("maia-tray-service: registering with the other watcher: {error}");
    }
    for service in other.registered_status_notifier_items().await.unwrap_or_default() {
        add(&service);
    }
    loop {
        tokio::select! {
            Some(signal) = registered.next() => {
                if let Ok(args) = signal.args() {
                    add(args.service());
                }
            }
            Some(signal) = unregistered.next() => {
                if let Ok(args) = signal.args() {
                    Hub::remove_service(&hub, args.service());
                }
            }
            Some(signal) = acquired.next() => {
                if signal.args().is_ok_and(|a| a.name() == NAME) {
                    eprintln!("maia-tray-service: the watcher now");
                    return;
                }
            }
            else => return,
        }
    }
}
