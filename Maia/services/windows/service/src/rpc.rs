//! The Cap'n Proto side of the service (contract ../contract/windows.capnp).
//!
//! `Hub` is the state shared by all connections: the window list and its listeners. Backend events
//! go in through `Hub::apply`, which updates the store and sends every real change to every
//! listener. A new listener first gets the whole list (snapshot) and then only the changes; Cap'n
//! Proto keeps the calls on one capability in order, so a client never sees a change before the
//! snapshot.
//!
//! Changes of one window go out at most once per frame, with its latest state (throttle.rs): a
//! window being dragged changes its geometry on every frame, and the clients need not hear each.
//!
//! Sending never waits for a client: every call is its own local task. A listener whose call fails
//! (the client went away) is dropped; so is one whose Subscription the client released.

use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::{mpsc, oneshot};
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::apps::AppIndex;
use crate::backend::{BackendEvent, BackendInfo, Command};
use crate::launch;
use crate::model::{Change, Window, WindowStore};
use crate::throttle::ChangeThrottle;
use crate::windows_capnp::{self as w, subscription, window, window_control, window_listener, window_service};

/// The changes of one window reach the clients at most this often: one frame at 60 Hz
pub const CHANGE_INTERVAL: Duration = Duration::from_millis(16);

/// The window list and who listens to it, shared by all connections
pub struct Hub {
    store: WindowStore,
    apps: AppIndex,
    listeners: Vec<(u64, window_listener::Client)>,
    next_listener: u64,
    throttle: ChangeThrottle,
    /// A timer runs that sends the waiting changes (flush)
    flush_scheduled: bool,
}

pub type HubRef = Rc<RefCell<Hub>>;

impl Hub {
    pub fn new(apps: AppIndex) -> HubRef {
        Rc::new(RefCell::new(Hub {
            store: WindowStore::new(),
            apps,
            listeners: Vec::new(),
            next_listener: 0,
            throttle: ChangeThrottle::new(CHANGE_INTERVAL),
            flush_scheduled: false,
        }))
    }

    pub fn store(&self) -> &WindowStore {
        &self.store
    }

    pub fn listener_count(&self) -> usize {
        self.listeners.len()
    }

    /// One event from the backend: update the list and tell the listeners what really changed
    pub fn apply(hub: &HubRef, event: BackendEvent) {
        let mut this = hub.borrow_mut();
        let Hub { store, apps, .. } = &mut *this;
        let change = match event {
            BackendEvent::Window(window) => {
                store.upsert(window, now_ms(), |w| apps.identify(&w.raw_app_id, &w.resource_name, w.pid))
            }
            BackendEvent::Removed(id) => store.remove(&id),
        };
        let Some(change) = change else { return };
        let now = Instant::now();
        let send_now = match &change {
            Change::Added(window) => {
                this.throttle.added(&window.id, now);
                true
            }
            Change::Changed(window) => this.throttle.changed(&window.id, now),
            Change::Removed(id) => {
                this.throttle.removed(id);
                true
            }
        };
        if send_now {
            this.broadcast(hub, &change);
        } else {
            schedule_flush(hub, &mut this);
        }
    }

    fn broadcast(&self, hub: &HubRef, change: &Change) {
        for (id, listener) in &self.listeners {
            send_change(hub, *id, listener, change);
        }
    }

    /// Sends the waiting changes that are due, each with the latest state of its window
    fn flush(hub: &HubRef) {
        let mut this = hub.borrow_mut();
        this.flush_scheduled = false;
        for id in this.throttle.take_due(Instant::now()) {
            if let Some(window) = this.store.get(&id).cloned() {
                this.broadcast(hub, &Change::Changed(window));
            }
        }
        schedule_flush(hub, &mut this);
    }

    /// Feeds the hub from the backend until the backend ends
    pub async fn run(hub: HubRef, mut events: mpsc::UnboundedReceiver<BackendEvent>) {
        while let Some(event) = events.recv().await {
            Hub::apply(&hub, event);
        }
    }

    fn add_listener(hub: &HubRef, client: window_listener::Client) -> u64 {
        let mut this = hub.borrow_mut();
        this.next_listener += 1;
        let id = this.next_listener;
        let mut request = client.snapshot_request();
        let windows = this.store.snapshot();
        let mut list = request.get().init_windows(windows.len() as u32);
        for (i, window) in windows.iter().enumerate() {
            write_window(list.reborrow().get(i as u32), window);
        }
        deliver(hub, id, request.send().promise);
        this.listeners.push((id, client));
        id
    }

    fn remove_listener(&mut self, id: u64) {
        self.listeners.retain(|(other, _)| *other != id);
    }
}

/// Starts the timer for the next waiting change, unless one runs or nothing waits
fn schedule_flush(hub: &HubRef, this: &mut Hub) {
    if this.flush_scheduled {
        return;
    }
    let Some(deadline) = this.throttle.next_deadline() else { return };
    this.flush_scheduled = true;
    let hub = Rc::downgrade(hub);
    tokio::task::spawn_local(async move {
        tokio::time::sleep_until(tokio::time::Instant::from_std(deadline)).await;
        if let Some(hub) = hub.upgrade() {
            Hub::flush(&hub);
        }
    });
}

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn send_change(hub: &HubRef, id: u64, listener: &window_listener::Client, change: &Change) {
    match change {
        Change::Added(window) => {
            let mut request = listener.added_request();
            write_window(request.get().init_window(), window);
            deliver(hub, id, request.send().promise);
        }
        Change::Changed(window) => {
            let mut request = listener.changed_request();
            write_window(request.get().init_window(), window);
            deliver(hub, id, request.send().promise);
        }
        Change::Removed(window_id) => {
            let mut request = listener.removed_request();
            request.get().set_id(window_id);
            deliver(hub, id, request.send().promise);
        }
    }
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

pub fn write_window(mut builder: window::Builder, window: &Window) {
    builder.set_id(&window.id);
    builder.set_title(&window.title);
    builder.set_raw_app_id(&window.raw_app_id);
    builder.set_icon_name(window.icon_name());
    builder.set_icon_serial(window.icon_serial);
    if let Some(app) = &window.app {
        builder.set_app_id(&app.desktop_id);
        builder.set_app_name(&app.name);
        builder.set_generic_name(&app.generic_name);
        builder.set_launcher_url(app.launcher_url());
        builder.set_can_launch_new_instance(!app.exec.is_empty());
    }
    builder.set_pid(window.pid);
    builder.set_states(window.states);
    {
        let mut rect = builder.reborrow().init_geometry();
        rect.set_x(window.geometry.x);
        rect.set_y(window.geometry.y);
        rect.set_width(window.geometry.width);
        rect.set_height(window.geometry.height);
    }
    let mut desktops = builder.reborrow().init_virtual_desktops(window.virtual_desktops.len() as u32);
    for (i, desktop) in window.virtual_desktops.iter().enumerate() {
        desktops.set(i as u32, desktop);
    }
    builder.set_parent_id(&window.parent_id);
    builder.set_last_activated(window.last_activated);
}

// --- WindowService: the bootstrap capability of every connection ---

/// The service object; `client()` gives the capability every connection starts with
pub struct WindowService {
    hub: HubRef,
    commands: mpsc::UnboundedSender<Command>,
    info: BackendInfo,
}

impl WindowService {
    pub fn client(hub: HubRef, commands: mpsc::UnboundedSender<Command>, info: BackendInfo) -> window_service::Client {
        capnp_rpc::new_client(WindowService { hub, commands, info })
    }
}

/// Released by the client (or with its connection): the listener stops getting calls
struct SubscriptionImpl {
    hub: Weak<RefCell<Hub>>,
    id: u64,
}

impl Drop for SubscriptionImpl {
    fn drop(&mut self) {
        if let Some(hub) = self.hub.upgrade() {
            hub.borrow_mut().remove_listener(self.id);
        }
    }
}

impl subscription::Server for SubscriptionImpl {}

impl window_service::Server for WindowService {
    async fn info(
        self: Rc<Self>,
        _: window_service::InfoParams,
        mut results: window_service::InfoResults,
    ) -> Result<(), capnp::Error> {
        let mut builder = results.get();
        builder.set_backend(&self.info.name);
        // Launching is done by the service itself, whatever the backend
        builder.set_capabilities(self.info.capabilities | w::CAP_LAUNCH);
        builder.set_service_version(env!("CARGO_PKG_VERSION"));
        Ok(())
    }

    async fn watch(
        self: Rc<Self>,
        params: window_service::WatchParams,
        mut results: window_service::WatchResults,
    ) -> Result<(), capnp::Error> {
        let listener = params.get()?.get_listener()?;
        let id = Hub::add_listener(&self.hub, listener);
        results.get().set_subscription(capnp_rpc::new_client(SubscriptionImpl { hub: Rc::downgrade(&self.hub), id }));
        Ok(())
    }

    async fn control(
        self: Rc<Self>,
        _: window_service::ControlParams,
        mut results: window_service::ControlResults,
    ) -> Result<(), capnp::Error> {
        let control = Control { hub: self.hub.clone(), commands: self.commands.clone() };
        results.get().set_control(capnp_rpc::new_client(control));
        Ok(())
    }

    async fn icon(
        self: Rc<Self>,
        params: window_service::IconParams,
        mut results: window_service::IconResults,
    ) -> Result<(), capnp::Error> {
        let id = params.get()?.get_id()?.to_string()?;
        let serial = self.hub.borrow().store.get(&id).map(|w| w.icon_serial).ok_or_else(|| no_window(&id))?;
        let (reply, data) = oneshot::channel();
        let data = match self.commands.send(Command::FetchIcon { id, reply }) {
            Ok(()) => data.await.unwrap_or_default(),
            Err(_) => Vec::new(),
        };
        let mut builder = results.get();
        builder.set_data(&data);
        builder.set_serial(serial);
        Ok(())
    }
}

// --- WindowControl ---

struct Control {
    hub: HubRef,
    commands: mpsc::UnboundedSender<Command>,
}

fn no_window(id: &str) -> capnp::Error {
    capnp::Error::failed(format!("no window {id}"))
}

impl Control {
    /// The id of a known window, or an error for the client
    fn window_id(&self, id: capnp::Result<capnp::text::Reader>) -> capnp::Result<String> {
        let id = id?.to_string()?;
        if self.hub.borrow().store.get(&id).is_none() {
            return Err(no_window(&id));
        }
        Ok(id)
    }

    fn send(&self, command: Command) -> capnp::Result<()> {
        self.commands.send(command).map_err(|_| capnp::Error::disconnected("the compositor backend has stopped".into()))
    }

    fn set_state(&self, id: String, flag: u32, on: bool) -> capnp::Result<()> {
        self.send(Command::SetState { id, flags: flag, state: if on { flag } else { 0 } })
    }
}

impl window_control::Server for Control {
    async fn activate(
        self: Rc<Self>,
        params: window_control::ActivateParams,
        _: window_control::ActivateResults,
    ) -> Result<(), capnp::Error> {
        let id = self.window_id(params.get()?.get_id())?;
        self.set_state(id, w::STATE_ACTIVE, true)
    }

    async fn close(
        self: Rc<Self>,
        params: window_control::CloseParams,
        _: window_control::CloseResults,
    ) -> Result<(), capnp::Error> {
        let id = self.window_id(params.get()?.get_id())?;
        self.send(Command::Close(id))
    }

    async fn set_minimized(
        self: Rc<Self>,
        params: window_control::SetMinimizedParams,
        _: window_control::SetMinimizedResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let id = self.window_id(params.get_id())?;
        self.set_state(id, w::STATE_MINIMIZED, params.get_minimized())
    }

    async fn set_maximized(
        self: Rc<Self>,
        params: window_control::SetMaximizedParams,
        _: window_control::SetMaximizedResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let id = self.window_id(params.get_id())?;
        self.set_state(id, w::STATE_MAXIMIZED, params.get_maximized())
    }

    async fn set_fullscreen(
        self: Rc<Self>,
        params: window_control::SetFullscreenParams,
        _: window_control::SetFullscreenResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let id = self.window_id(params.get_id())?;
        self.set_state(id, w::STATE_FULLSCREEN, params.get_fullscreen())
    }

    async fn set_keep_above(
        self: Rc<Self>,
        params: window_control::SetKeepAboveParams,
        _: window_control::SetKeepAboveResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let id = self.window_id(params.get_id())?;
        self.set_state(id, w::STATE_KEEP_ABOVE, params.get_keep_above())
    }

    async fn set_keep_below(
        self: Rc<Self>,
        params: window_control::SetKeepBelowParams,
        _: window_control::SetKeepBelowResults,
    ) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let id = self.window_id(params.get_id())?;
        self.set_state(id, w::STATE_KEEP_BELOW, params.get_keep_below())
    }

    async fn request_move(
        self: Rc<Self>,
        params: window_control::RequestMoveParams,
        _: window_control::RequestMoveResults,
    ) -> Result<(), capnp::Error> {
        let id = self.window_id(params.get()?.get_id())?;
        self.send(Command::RequestMove(id))
    }

    async fn request_resize(
        self: Rc<Self>,
        params: window_control::RequestResizeParams,
        _: window_control::RequestResizeResults,
    ) -> Result<(), capnp::Error> {
        let id = self.window_id(params.get()?.get_id())?;
        self.send(Command::RequestResize(id))
    }

    async fn launch_new_instance(
        self: Rc<Self>,
        params: window_control::LaunchNewInstanceParams,
        _: window_control::LaunchNewInstanceResults,
    ) -> Result<(), capnp::Error> {
        let id = self.window_id(params.get()?.get_id())?;
        let app = self.hub.borrow().store.get(&id).and_then(|w| w.app.clone());
        let app = app.ok_or_else(|| capnp::Error::failed(format!("the application of window {id} is unknown")))?;
        launch::launch(&app).map_err(|error| capnp::Error::failed(format!("{}: {error}", app.desktop_id)))
    }

    async fn launch(
        self: Rc<Self>,
        params: window_control::LaunchParams,
        _: window_control::LaunchResults,
    ) -> Result<(), capnp::Error> {
        let url = params.get()?.get_launcher_url()?.to_string()?;
        let app = self.hub.borrow().apps.by_launcher_url(&url);
        let app = app.ok_or_else(|| capnp::Error::failed(format!("no application for {url}")))?;
        launch::launch(&app).map_err(|error| capnp::Error::failed(format!("{}: {error}", app.desktop_id)))
    }
}

// --- Connections ---

/// Serves one client connection in the background
pub fn serve(stream: tokio::net::UnixStream, service: window_service::Client) {
    let (reader, writer) = stream.compat().split();
    let network = twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Server,
        Default::default(),
    );
    let rpc_system = RpcSystem::new(Box::new(network), Some(service.client));
    tokio::task::spawn_local(async move {
        if let Err(error) = rpc_system.await {
            eprintln!("maia-windows: connection ended: {error}");
        }
    });
}
