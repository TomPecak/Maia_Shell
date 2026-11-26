//! Test helpers: a private D-Bus session bus, the service on it (watcher and host), applications
//! with an item and a menu (zbus servers, as KStatusNotifierItem and libdbusmenu are), and a shell
//! watching the service over Cap'n Proto.

#![allow(dead_code)]

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::io::BufRead;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio_util::compat::TokioAsyncReadCompatExt;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, StructureBuilder, Value};

use maia_tray::hub::{Hub, HubRef};
use maia_tray::image::ImageStore;
use maia_tray::rpc::{self, Host};
use maia_tray::tray_capnp::{self as t, menu_listener, tray_host, tray_listener};

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
        let dir = std::env::temp_dir().join(format!("maia-tray-{name}-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(dir)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// --- The service ---

pub struct Service {
    pub hub: HubRef,
    pub connection: zbus::Connection,
    pub images: TempDir,
    /// Whether it got the watcher's name
    pub watcher: bool,
}

impl Service {
    pub async fn start(bus: &Bus) -> Service {
        let images = TempDir::new("images");
        let connection = bus.connect().await;
        let hub = Hub::new(ImageStore::new(Some(images.0.clone())), Some(connection.clone()));
        let watcher = maia_tray::watcher::serve(&connection, &hub).await.unwrap();
        Service { hub, connection, images, watcher }
    }
}

// --- An application with an item ---

/// What an application's item says; the test changes it and sends a signal
#[derive(Clone, Debug)]
pub struct ItemState {
    pub id: String,
    pub title: String,
    pub status: String,
    pub category: String,
    pub icon_name: String,
    pub icon_pixmap: Vec<(i32, i32, Vec<u8>)>,
    pub attention_icon_name: String,
    pub tool_tip: (String, Vec<(i32, i32, Vec<u8>)>, String, String),
    pub item_is_menu: bool,
    pub menu: String,
    /// GetAll calls so far (each reads Title once)
    pub reads: u32,
}

impl Default for ItemState {
    fn default() -> Self {
        ItemState {
            id: "org.example.chat".into(),
            title: "Chat".into(),
            status: "Active".into(),
            category: "Communications".into(),
            icon_name: "chat".into(),
            icon_pixmap: Vec::new(),
            attention_icon_name: String::new(),
            tool_tip: (String::new(), Vec::new(), "Chat".into(), "2 <b>new</b> messages".into()),
            item_is_menu: false,
            menu: "/MenuBar".into(),
            reads: 0,
        }
    }
}

pub type Calls = Arc<Mutex<Vec<String>>>;

struct ItemIface {
    state: Arc<Mutex<ItemState>>,
    calls: Calls,
}

#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl ItemIface {
    #[zbus(property)]
    fn id(&self) -> String {
        self.state.lock().unwrap().id.clone()
    }
    #[zbus(property)]
    fn title(&self) -> String {
        let mut state = self.state.lock().unwrap();
        state.reads += 1;
        state.title.clone()
    }
    #[zbus(property)]
    fn status(&self) -> String {
        self.state.lock().unwrap().status.clone()
    }
    #[zbus(property)]
    fn category(&self) -> String {
        self.state.lock().unwrap().category.clone()
    }
    #[zbus(property)]
    fn icon_name(&self) -> String {
        self.state.lock().unwrap().icon_name.clone()
    }
    #[zbus(property)]
    fn icon_pixmap(&self) -> Vec<(i32, i32, Vec<u8>)> {
        self.state.lock().unwrap().icon_pixmap.clone()
    }
    #[zbus(property)]
    fn attention_icon_name(&self) -> String {
        self.state.lock().unwrap().attention_icon_name.clone()
    }
    #[zbus(property)]
    fn tool_tip(&self) -> (String, Vec<(i32, i32, Vec<u8>)>, String, String) {
        self.state.lock().unwrap().tool_tip.clone()
    }
    #[zbus(property)]
    fn item_is_menu(&self) -> bool {
        self.state.lock().unwrap().item_is_menu
    }
    #[zbus(property)]
    fn menu(&self) -> OwnedObjectPath {
        let menu = self.state.lock().unwrap().menu.clone();
        OwnedObjectPath::try_from(if menu.is_empty() { "/".to_string() } else { menu }).unwrap()
    }

    fn activate(&self, x: i32, y: i32) {
        self.calls.lock().unwrap().push(format!("Activate {x} {y}"));
    }
    fn secondary_activate(&self, x: i32, y: i32) {
        self.calls.lock().unwrap().push(format!("SecondaryActivate {x} {y}"));
    }
    fn context_menu(&self, x: i32, y: i32) {
        self.calls.lock().unwrap().push(format!("ContextMenu {x} {y}"));
    }
    fn scroll(&self, delta: i32, orientation: String) {
        self.calls.lock().unwrap().push(format!("Scroll {delta} {orientation}"));
    }
    fn provide_xdg_activation_token(&self, token: String) {
        self.calls.lock().unwrap().push(format!("Token {token}"));
    }

    #[zbus(signal)]
    async fn new_icon(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn new_title(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn new_status(emitter: &SignalEmitter<'_>, status: &str) -> zbus::Result<()>;
}

/// One entry of a fake menu: (id, label, children)
#[derive(Clone, Debug)]
pub struct FakeEntry {
    pub id: i32,
    pub props: Vec<(String, OwnedValue)>,
    pub children: Vec<FakeEntry>,
}

pub fn entry(id: i32, label: &str, children: Vec<FakeEntry>) -> FakeEntry {
    let mut props = vec![("label".to_string(), OwnedValue::try_from(Value::from(label)).unwrap())];
    if !children.is_empty() {
        props.push(("children-display".to_string(), OwnedValue::try_from(Value::from("submenu")).unwrap()));
    }
    FakeEntry { id, props, children }
}

fn layout_of(entry: &FakeEntry) -> (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>) {
    let props = entry.props.iter().map(|(k, v)| (k.clone(), v.try_clone().unwrap())).collect();
    let children = entry
        .children
        .iter()
        .map(|child| {
            let (id, props, children) = layout_of(child);
            let value = Value::Structure(StructureBuilder::new().add_field(id).add_field(props).add_field(children).build().unwrap());
            OwnedValue::try_from(value).unwrap()
        })
        .collect();
    (entry.id, props, children)
}

struct MenuIface {
    root: Arc<Mutex<FakeEntry>>,
    calls: Calls,
}

#[zbus::interface(name = "com.canonical.dbusmenu")]
impl MenuIface {
    fn get_layout(&self, parent: i32, _depth: i32, _props: Vec<String>) -> (u32, (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>)) {
        self.calls.lock().unwrap().push(format!("GetLayout {parent}"));
        (1, layout_of(&self.root.lock().unwrap()))
    }
    fn about_to_show(&self, id: i32) -> bool {
        self.calls.lock().unwrap().push(format!("AboutToShow {id}"));
        false
    }
    fn event(&self, id: i32, event_id: String, _data: OwnedValue, _timestamp: u32) {
        self.calls.lock().unwrap().push(format!("Event {id} {event_id}"));
    }
    #[zbus(property)]
    fn version(&self) -> u32 {
        3
    }
    #[zbus(signal)]
    async fn layout_updated(emitter: &SignalEmitter<'_>, revision: u32, parent: i32) -> zbus::Result<()>;
}

pub struct App {
    pub connection: zbus::Connection,
    pub state: Arc<Mutex<ItemState>>,
    pub calls: Calls,
    pub menu: Arc<Mutex<FakeEntry>>,
    pub path: String,
    pub name: String,
}

impl App {
    /// An application with an item at `path` (and its menu at /MenuBar), registered with the
    /// watcher by its bus name (`by_name`, as KStatusNotifierItem) or by its path (libappindicator)
    pub async fn start(bus: &Bus, state: ItemState, path: &str, by_name: bool) -> App {
        let app = App::serve(bus, state, path, by_name).await;
        app.register(if by_name { &app.name } else { path }).await;
        app
    }

    /// The application without its registration
    pub async fn serve(bus: &Bus, state: ItemState, path: &str, by_name: bool) -> App {
        let connection = bus.connect().await;
        let state = Arc::new(Mutex::new(state));
        let calls: Calls = Arc::default();
        let menu = Arc::new(Mutex::new(entry(0, "", vec![entry(1, "_Show", vec![]), entry(2, "Quit", vec![])])));
        connection.object_server().at(path, ItemIface { state: state.clone(), calls: calls.clone() }).await.unwrap();
        connection.object_server().at("/MenuBar", MenuIface { root: menu.clone(), calls: calls.clone() }).await.unwrap();
        let name = if by_name {
            let name = format!("org.kde.StatusNotifierItem-{}-{}", std::process::id(), connection.unique_name().unwrap().trim_start_matches(':').replace('.', "_"));
            connection.request_name(name.as_str()).await.unwrap();
            name
        } else {
            connection.unique_name().unwrap().to_string()
        };
        App { connection, state, calls, menu, path: path.to_string(), name }
    }

    pub async fn register(&self, service: &str) {
        self.connection
            .call_method(Some("org.kde.StatusNotifierWatcher"), "/StatusNotifierWatcher", Some("org.kde.StatusNotifierWatcher"), "RegisterStatusNotifierItem", &(service,))
            .await
            .unwrap();
    }

    pub fn set(&self, change: impl FnOnce(&mut ItemState)) {
        change(&mut self.state.lock().unwrap());
    }

    pub async fn new_icon(&self) {
        let emitter = SignalEmitter::new(&self.connection, self.path.as_str()).unwrap();
        ItemIface::new_icon(&emitter).await.unwrap();
    }

    pub async fn new_status(&self, status: &str) {
        let emitter = SignalEmitter::new(&self.connection, self.path.as_str()).unwrap();
        ItemIface::new_status(&emitter, status).await.unwrap();
    }

    pub async fn layout_updated(&self) {
        let emitter = SignalEmitter::new(&self.connection, "/MenuBar").unwrap();
        MenuIface::layout_updated(&emitter, 2, 0).await.unwrap();
    }

    pub fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }

    pub fn reads(&self) -> u32 {
        self.state.lock().unwrap().reads
    }
}

/// An opaque red square, ARGB32 in network byte order
pub fn red(side: i32) -> (i32, i32, Vec<u8>) {
    (side, side, [255u8, 255, 0, 0].repeat((side * side) as usize))
}

// --- A shell ---

#[derive(Clone, Debug, PartialEq)]
pub struct Shown {
    pub key: String,
    pub title: String,
    pub status: t::Status,
    pub category: t::Category,
    pub icon_name: String,
    pub icon_url: String,
    pub icon_mask: bool,
    pub attention_icon_name: String,
    pub tool_tip_title: String,
    pub tool_tip_text: String,
    pub has_menu: bool,
    pub item_is_menu: bool,
}

#[derive(Default, Debug)]
pub struct Seen {
    pub snapshots: u32,
    pub batches: u32,
    pub items: BTreeMap<u32, Shown>,
}

fn read(i: t::item::Reader) -> capnp::Result<(u32, Shown)> {
    let tip = i.get_tool_tip()?;
    Ok((
        i.get_id(),
        Shown {
            key: i.get_key()?.to_string()?,
            title: i.get_title()?.to_string()?,
            status: i.get_status()?,
            category: i.get_category()?,
            icon_name: i.get_icon()?.get_name()?.to_string()?,
            icon_url: i.get_icon()?.get_url()?.to_string()?,
            icon_mask: i.get_icon()?.get_mask(),
            attention_icon_name: i.get_attention_icon()?.get_name()?.to_string()?,
            tool_tip_title: tip.get_title()?.to_string()?,
            tool_tip_text: tip.get_text()?.to_string()?,
            has_menu: i.get_has_menu(),
            item_is_menu: i.get_item_is_menu(),
        },
    ))
}

struct ShellListener(Rc<RefCell<Seen>>);

impl tray_listener::Server for ShellListener {
    async fn snapshot(self: Rc<Self>, params: tray_listener::SnapshotParams, _: tray_listener::SnapshotResults) -> Result<(), capnp::Error> {
        let mut seen = self.0.borrow_mut();
        seen.snapshots += 1;
        seen.items.clear();
        for item in params.get()?.get_items()? {
            let (id, shown) = read(item)?;
            seen.items.insert(id, shown);
        }
        Ok(())
    }

    async fn changes(self: Rc<Self>, params: tray_listener::ChangesParams, _: tray_listener::ChangesResults) -> Result<(), capnp::Error> {
        let params = params.get()?;
        let mut seen = self.0.borrow_mut();
        seen.batches += 1;
        for item in params.get_changed()? {
            let (id, shown) = read(item)?;
            seen.items.insert(id, shown);
        }
        for id in params.get_removed()? {
            seen.items.remove(&id);
        }
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
    pub host: tray_host::Client,
    subscription: Option<t::subscription::Client>,
}

impl Shell {
    pub async fn connect(hub: &HubRef) -> Shell {
        let (ours, theirs) = tokio::net::UnixStream::pair().unwrap();
        rpc::serve(theirs, Host::client(hub.clone()).client);
        let host: tray_host::Client = twoparty(ours);
        let seen = Rc::new(RefCell::new(Seen::default()));
        let mut request = host.watch_request();
        request.get().set_listener(capnp_rpc::new_client(ShellListener(seen.clone())));
        let subscription = request.send().promise.await.unwrap().get().unwrap().get_subscription().unwrap();
        let shell = Shell { seen, host, subscription: Some(subscription) };
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

    /// The only item the shell has
    pub fn single(&self) -> (u32, Shown) {
        let seen = self.seen.borrow();
        assert_eq!(seen.items.len(), 1, "{seen:#?}");
        let (id, shown) = seen.items.iter().next().unwrap();
        (*id, shown.clone())
    }

    pub async fn activate(&self, id: u32, token: &str) -> t::ErrorCode {
        let mut request = self.host.activate_request();
        request.get().set_id(id);
        request.get().set_x(10);
        request.get().set_y(20);
        request.get().set_activation_token(token);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }
}

// --- A shell's open menu ---

#[derive(Default, Debug)]
pub struct MenuSeen {
    pub layouts: u32,
    /// The labels of the last layout, a submenu's after its own in brackets: "Show, Status [Online]"
    pub labels: String,
    pub ids: Vec<i32>,
    pub closed: bool,
}

fn labels(entries: capnp::struct_list::Reader<t::menu_entry::Owned>, ids: &mut Vec<i32>) -> capnp::Result<String> {
    let mut parts = Vec::new();
    for entry in entries {
        ids.push(entry.get_id());
        let mut part = entry.get_label()?.to_string()?;
        if entry.get_separator() {
            part = "-".into();
        }
        let children = entry.get_children()?;
        if !children.is_empty() {
            part = format!("{part} [{}]", labels(children, ids)?);
        }
        parts.push(part);
    }
    Ok(parts.join(", "))
}

struct MenuListenerImpl(Rc<RefCell<MenuSeen>>);

impl menu_listener::Server for MenuListenerImpl {
    async fn layout(self: Rc<Self>, params: menu_listener::LayoutParams, _: menu_listener::LayoutResults) -> Result<(), capnp::Error> {
        let mut seen = self.0.borrow_mut();
        seen.layouts += 1;
        seen.ids.clear();
        let mut ids = Vec::new();
        seen.labels = labels(params.get()?.get_entries()?, &mut ids)?;
        seen.ids = ids;
        Ok(())
    }

    async fn closed(self: Rc<Self>, _: menu_listener::ClosedParams, _: menu_listener::ClosedResults) -> Result<(), capnp::Error> {
        self.0.borrow_mut().closed = true;
        Ok(())
    }
}

pub struct OpenMenu {
    pub seen: Rc<RefCell<MenuSeen>>,
    pub menu: Option<t::menu::Client>,
    pub error: t::ErrorCode,
}

impl OpenMenu {
    pub async fn open(shell: &Shell, id: u32) -> OpenMenu {
        let seen = Rc::new(RefCell::new(MenuSeen::default()));
        let mut request = shell.host.open_menu_request();
        request.get().set_id(id);
        request.get().set_listener(capnp_rpc::new_client(MenuListenerImpl(seen.clone())));
        let reply = request.send().promise.await.unwrap();
        let reply = reply.get().unwrap();
        let error = reply.get_result().unwrap().get_error().unwrap();
        let menu = if error == t::ErrorCode::None { Some(reply.get_menu().unwrap()) } else { None };
        OpenMenu { seen, menu, error }
    }

    pub async fn wait(&self, what: &str, condition: impl Fn(&MenuSeen) -> bool) {
        let start = Instant::now();
        while !condition(&self.seen.borrow()) {
            assert!(start.elapsed() < TIMEOUT, "waiting for {what}: {:#?}", self.seen.borrow());
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    }

    pub async fn activate(&self, entry: i32, token: &str) -> t::ErrorCode {
        let mut request = self.menu.as_ref().unwrap().activate_request();
        request.get().set_entry_id(entry);
        request.get().set_activation_token(token);
        request.send().promise.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap()
    }
}
