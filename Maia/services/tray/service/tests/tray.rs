//! The service on a private session bus, with applications that show items the way Qt (by bus
//! name) and libappindicator (by object path) do, and a shell over Cap'n Proto.

mod common;

use std::time::Duration;

use common::*;
use futures::StreamExt;
use maia_tray::tray_capnp as t;

#[zbus::proxy(interface = "org.kde.StatusNotifierWatcher", default_service = "org.kde.StatusNotifierWatcher", default_path = "/StatusNotifierWatcher", gen_blocking = false)]
trait Watcher {
    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> zbus::Result<Vec<String>>;
    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn protocol_version(&self) -> zbus::Result<i32>;
    #[zbus(signal)]
    fn status_notifier_item_registered(&self, service: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    fn status_notifier_item_unregistered(&self, service: &str) -> zbus::Result<()>;
}

async fn watcher(bus: &Bus) -> WatcherProxy<'static> {
    let connection = bus.connect().await;
    WatcherProxy::builder(&connection).cache_properties(zbus::proxy::CacheProperties::No).build().await.unwrap()
}

#[test]
fn an_item_registered_by_its_bus_name_is_shown() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        assert!(service.watcher);
        let shell = Shell::connect(&service.hub).await;
        assert!(shell.seen.borrow().items.is_empty());
        let watcher = watcher(&bus).await;
        assert!(watcher.is_status_notifier_host_registered().await.unwrap());
        assert_eq!(watcher.protocol_version().await.unwrap(), 0);
        let mut registered = watcher.receive_status_notifier_item_registered().await.unwrap();

        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        let (_, item) = shell.single();
        assert_eq!(item.title, "Chat");
        assert_eq!(item.key, "org.example.chat");
        assert_eq!(item.status, t::Status::Active);
        assert_eq!(item.category, t::Category::Communications);
        assert_eq!(item.icon_name, "chat");
        assert_eq!(item.tool_tip_title, "Chat");
        assert_eq!(item.tool_tip_text, "2 new messages");
        assert!(item.has_menu && !item.item_is_menu);

        let service_string = format!("{}/StatusNotifierItem", app.name);
        assert_eq!(watcher.registered_status_notifier_items().await.unwrap(), [service_string.clone()]);
        let signal = tokio::time::timeout(TIMEOUT, registered.next()).await.unwrap().unwrap();
        assert_eq!(*signal.args().unwrap().service(), service_string);

        // Registered again (an application that restarts its item): still one
        app.register(&app.name).await;
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(shell.seen.borrow().items.len(), 1);
    });
}

#[test]
fn an_item_registered_by_its_path_is_shown() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let state = ItemState { id: "app-indicator".into(), menu: String::new(), ..ItemState::default() };
        let app = App::start(&bus, state, "/org/ayatana/NotificationItem/app", false).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        assert!(!shell.single().1.has_menu);
        let listed = watcher(&bus).await.registered_status_notifier_items().await.unwrap();
        assert_eq!(listed, [format!("{}/org/ayatana/NotificationItem/app", app.name)]);
    });
}

#[test]
fn pixels_become_small_png_files() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let state = ItemState { icon_name: String::new(), icon_pixmap: vec![red(16), red(128), red(256)], ..ItemState::default() };
        let _app = App::start(&bus, state, "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        let (_, item) = shell.single();
        assert_eq!(item.icon_name, "");
        let file = std::path::PathBuf::from(item.icon_url.strip_prefix("file://").expect("a file URL"));
        assert!(file.starts_with(&service.images.0));
        let decoder = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(&file).unwrap()));
        let reader = decoder.read_info().unwrap();
        assert_eq!((reader.info().width, reader.info().height), (64, 64));
        // Red: a picture, drawn as it is
        assert!(!item.icon_mask);
    });
}

#[test]
fn a_black_template_icon_is_a_mask_for_the_shells() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        // As Claude's or an Electron application's: black pixels, the shape in the transparency
        let black = |side: i32| (side, side, [255u8, 0, 0, 0, 0, 0, 0, 0].repeat((side * side / 2) as usize));
        let state = ItemState { icon_name: String::new(), icon_pixmap: vec![black(64)], ..ItemState::default() };
        let app = App::start(&bus, state, "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        assert!(shell.single().1.icon_mask);
        // A new icon in colour is no mask any more
        app.set(|s| s.icon_pixmap = vec![red(64)]);
        app.new_icon().await;
        shell.wait("the colour", |s| s.items.values().all(|i| !i.icon_mask)).await;
    });
}

#[test]
fn changes_follow_the_signals_and_bursts_are_one_read() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;

        app.set(|s| {
            s.status = "NeedsAttention".into();
            s.attention_icon_name = "chat-new".into();
        });
        app.new_status("NeedsAttention").await;
        shell.wait("attention", |s| s.items.values().all(|i| i.status == t::Status::NeedsAttention)).await;
        assert_eq!(shell.single().1.attention_icon_name, "chat-new");

        // An animated icon: 30 changes as fast as they can go
        let reads_before = app.reads();
        let batches_before = shell.seen.borrow().batches;
        for frame in 0..30 {
            app.set(|s| s.icon_name = format!("frame-{frame}"));
            app.new_icon().await;
        }
        shell.wait("the last frame", |s| s.items.values().all(|i| i.icon_name == "frame-29")).await;
        let reads = app.reads() - reads_before;
        assert!(reads <= 4, "{reads} reads for one burst");
        assert!(shell.seen.borrow().batches - batches_before <= 4);

        // A signal without a change: nothing for the shell
        let batches = shell.seen.borrow().batches;
        app.new_icon().await;
        tokio::time::sleep(Duration::from_millis(250)).await;
        assert_eq!(shell.seen.borrow().batches, batches);
    });
}

#[test]
fn an_item_goes_with_its_application() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let watcher = watcher(&bus).await;
        let mut unregistered = watcher.receive_status_notifier_item_unregistered().await.unwrap();
        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        drop(app);
        shell.wait("no item", |s| s.items.is_empty()).await;
        assert!(watcher.registered_status_notifier_items().await.unwrap().is_empty());
        assert!(tokio::time::timeout(TIMEOUT, unregistered.next()).await.unwrap().is_some());
    });
}

#[test]
fn an_item_that_cannot_be_read_is_never_shown() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        // A connection that registers a path it does not serve (it answers: no such object)
        let connection = bus.connect().await;
        let _ = connection.object_server();
        connection
            .call_method(Some("org.kde.StatusNotifierWatcher"), "/StatusNotifierWatcher", Some("org.kde.StatusNotifierWatcher"), "RegisterStatusNotifierItem", &("/Nothing",))
            .await
            .unwrap();
        // And a name nobody owns
        connection
            .call_method(Some("org.kde.StatusNotifierWatcher"), "/StatusNotifierWatcher", Some("org.kde.StatusNotifierWatcher"), "RegisterStatusNotifierItem", &("org.example.Nobody",))
            .await
            .unwrap();
        let watcher = watcher(&bus).await;
        eventually("both dropped", || service.hub.borrow().get(1).is_none() && service.hub.borrow().get(2).is_none()).await;
        assert!(watcher.registered_status_notifier_items().await.unwrap().is_empty());
        assert_eq!(shell.seen.borrow().batches, 0);
        // A registration that is neither a name nor a path is refused
        let refused = connection
            .call_method(Some("org.kde.StatusNotifierWatcher"), "/StatusNotifierWatcher", Some("org.kde.StatusNotifierWatcher"), "RegisterStatusNotifierItem", &("no such thing!",))
            .await;
        assert!(refused.is_err());
    });
}

#[test]
fn clicks_reach_the_application_with_the_token_first() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        let (id, _) = shell.single();

        assert_eq!(shell.activate(id, "token-1").await, t::ErrorCode::None);
        eventually("Activate", || app.calls().contains(&"Activate 10 20".to_string())).await;
        let calls = app.calls();
        let token = calls.iter().position(|c| c == "Token token-1").expect("the token");
        assert!(token < calls.iter().position(|c| c == "Activate 10 20").unwrap());

        let mut request = shell.host.secondary_activate_request();
        request.get().set_id(id);
        request.send().promise.await.unwrap();
        let mut request = shell.host.scroll_request();
        request.get().set_id(id);
        request.get().set_delta(-120);
        request.get().set_orientation(t::Orientation::Horizontal);
        request.send().promise.await.unwrap();
        let mut request = shell.host.context_menu_request();
        request.get().set_id(id);
        request.get().set_x(1);
        request.get().set_y(2);
        request.send().promise.await.unwrap();
        for expected in ["SecondaryActivate 0 0", "Scroll -120 horizontal", "ContextMenu 1 2"] {
            eventually(expected, || app.calls().iter().any(|c| c == expected)).await;
        }

        assert_eq!(shell.activate(999, "").await, t::ErrorCode::NotFound);
    });
}

#[test]
fn a_menu_is_read_followed_and_clicked() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        shell.wait("the item", |s| s.items.len() == 1).await;
        let (id, _) = shell.single();

        let menu = OpenMenu::open(&shell, id).await;
        assert_eq!(menu.error, t::ErrorCode::None);
        menu.wait("the layout", |m| m.layouts == 1).await;
        assert_eq!(menu.seen.borrow().labels, "Show, Quit");
        eventually("opened", || app.calls().iter().any(|c| c == "Event 0 opened")).await;
        assert!(app.calls().iter().position(|c| c == "AboutToShow 0") < app.calls().iter().position(|c| c == "GetLayout 0"));

        // The application changes its menu
        *app.menu.lock().unwrap() = entry(0, "", vec![entry(1, "_Show", vec![]), entry(3, "Status", vec![entry(4, "Online", vec![])]), entry(2, "Quit", vec![])]);
        app.layout_updated().await;
        menu.wait("the new layout", |m| m.labels == "Show, Status [Online], Quit").await;

        assert_eq!(menu.activate(4, "token-2").await, t::ErrorCode::None);
        eventually("clicked", || app.calls().iter().any(|c| c == "Event 4 clicked")).await;
        assert!(app.calls().iter().any(|c| c == "Token token-2"));
        assert_eq!(menu.activate(77, "").await, t::ErrorCode::NotFound);

        // Dropped by the shell: closed for the application
        drop(menu);
        eventually("closed", || app.calls().iter().any(|c| c == "Event 0 closed")).await;
        eventually("no menus", || service.hub.borrow().menu_count() == 0).await;
    });
}

#[test]
fn an_open_menu_closes_when_its_item_goes_and_items_without_a_menu_have_none() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        let plain = App::start(&bus, ItemState { id: "plain".into(), menu: String::new(), ..ItemState::default() }, "/StatusNotifierItem", true).await;
        shell.wait("two items", |s| s.items.len() == 2).await;
        let ids: Vec<u32> = shell.seen.borrow().items.keys().copied().collect();

        assert_eq!(OpenMenu::open(&shell, ids[1]).await.error, t::ErrorCode::InvalidArgument);
        drop(plain);

        let menu = OpenMenu::open(&shell, ids[0]).await;
        menu.wait("the layout", |m| m.layouts == 1).await;
        drop(app);
        menu.wait("closed", |m| m.closed).await;
        shell.wait("no items", |s| s.items.is_empty()).await;
    });
}

#[test]
fn every_shell_gets_the_items_and_a_shell_that_leaves_is_forgotten() {
    let bus = Bus::start();
    local(async {
        let service = Service::start(&bus).await;
        let first = Shell::connect(&service.hub).await;
        let _app = App::start(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        first.wait("the item", |s| s.items.len() == 1).await;
        let second = Shell::connect(&service.hub).await;
        assert_eq!(second.single().1, first.single().1);
        assert_eq!(service.hub.borrow().listener_count(), 2);
        drop(first);
        eventually("one shell", || service.hub.borrow().listener_count() == 1).await;
    });
}

/// A watcher of another program (Plasma's kded), with one item registered
struct OtherWatcher {
    items: Vec<String>,
    hosts: std::sync::Arc<std::sync::Mutex<Vec<String>>>,
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl OtherWatcher {
    fn register_status_notifier_host(&self, service: String) {
        self.hosts.lock().unwrap().push(service);
    }
    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.clone()
    }
}

#[test]
fn with_another_watcher_the_service_is_its_host_until_it_ends() {
    let bus = Bus::start();
    local(async {
        // An application, and a watcher that knows its item, before the service starts
        let app = App::serve(&bus, ItemState::default(), "/StatusNotifierItem", true).await;
        let other = bus.connect().await;
        let hosts = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        other.object_server().at("/StatusNotifierWatcher", OtherWatcher { items: vec![format!("{}/StatusNotifierItem", app.name)], hosts: hosts.clone() }).await.unwrap();
        other.request_name("org.kde.StatusNotifierWatcher").await.unwrap();

        let service = Service::start(&bus).await;
        assert!(!service.watcher);
        let shell = Shell::connect(&service.hub).await;
        shell.wait("the other watcher's item", |s| s.items.len() == 1).await;
        assert_eq!(hosts.lock().unwrap().as_slice(), [maia_tray::watcher::host_name()]);

        // The other watcher ends: the name is the service's now
        drop(other);
        let watcher = watcher(&bus).await;
        let start = std::time::Instant::now();
        loop {
            let owner = zbus::fdo::DBusProxy::new(&service.connection).await.unwrap().get_name_owner("org.kde.StatusNotifierWatcher".try_into().unwrap()).await;
            if owner.is_ok_and(|o| o.as_str() == service.connection.unique_name().unwrap().as_str()) {
                break;
            }
            assert!(start.elapsed() < TIMEOUT, "the name");
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        assert!(watcher.is_status_notifier_host_registered().await.unwrap());
        assert_eq!(shell.seen.borrow().items.len(), 1);
    });
}
