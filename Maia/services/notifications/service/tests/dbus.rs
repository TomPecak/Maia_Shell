//! The D-Bus door against a private dbus-daemon: clients call org.freedesktop.Notifications as
//! every application does (notify-send, libnotify, KNotification), a shell watches the list over
//! Cap'n Proto, and the clients' signals are checked in their order.

mod common;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::{Duration, Instant};

use common::{Bus, Shell, TempDir, local};
use futures::StreamExt;
use maia_notifications::dbus;
use maia_notifications::hub::HubRef;
use maia_notifications::model::MAX_NOTIFICATIONS;
use maia_notifications::notifications_capnp as n;
use zbus::zvariant::Value;

#[zbus::proxy(
    interface = "org.freedesktop.Notifications",
    default_service = "org.freedesktop.Notifications",
    default_path = "/org/freedesktop/Notifications"
)]
trait Notifications {
    #[allow(clippy::too_many_arguments)]
    fn notify(
        &self,
        app_name: &str,
        replaces_id: u32,
        app_icon: &str,
        summary: &str,
        body: &str,
        actions: &[&str],
        hints: HashMap<&str, Value<'_>>,
        expire_timeout: i32,
    ) -> zbus::Result<u32>;
    fn close_notification(&self, id: u32) -> zbus::Result<()>;
    fn get_capabilities(&self) -> zbus::Result<Vec<String>>;
    fn get_server_information(&self) -> zbus::Result<(String, String, String, String)>;
    fn inhibit(&self, desktop_entry: &str, reason: &str, hints: HashMap<&str, Value<'_>>) -> zbus::Result<u32>;
    fn un_inhibit(&self, cookie: u32) -> zbus::Result<()>;
    #[zbus(property)]
    fn inhibited(&self) -> zbus::Result<bool>;
}

struct Service {
    hub: HubRef,
    _connection: zbus::Connection,
}

async fn service(bus: &Bus, dir: &TempDir) -> Service {
    let connection = bus.connect().await;
    let hub = common::hub(dir);
    dbus::serve(&connection, &hub).await.unwrap();
    assert!(dbus::take_name(&connection).await.unwrap());
    Service { hub, _connection: connection }
}

/// An application on the bus, recording the signals it gets in their order
struct App {
    connection: zbus::Connection,
    proxy: NotificationsProxy<'static>,
    signals: Rc<RefCell<Vec<String>>>,
}

impl App {
    async fn connect(bus: &Bus) -> App {
        let connection = bus.connect().await;
        let proxy = NotificationsProxy::new(&connection).await.unwrap();
        let signals = Rc::new(RefCell::new(Vec::new()));
        let rule = zbus::MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.Notifications")
            .unwrap()
            .build();
        let mut stream = zbus::MessageStream::for_match_rule(rule, &connection, None).await.unwrap();
        let recorded = signals.clone();
        tokio::task::spawn_local(async move {
            while let Some(Ok(message)) = stream.next().await {
                let header = message.header();
                let member = header.member().map(|m| m.to_string()).unwrap_or_default();
                let body = message.body();
                let line = match member.as_str() {
                    "NotificationClosed" => body.deserialize::<(u32, u32)>().map(|(id, r)| format!("closed {id} {r}")),
                    "ActionInvoked" => body.deserialize::<(u32, String)>().map(|(id, k)| format!("action {id} {k}")),
                    "ActivationToken" => body.deserialize::<(u32, String)>().map(|(id, t)| format!("token {id} {t}")),
                    "NotificationReplied" => body.deserialize::<(u32, String)>().map(|(id, t)| format!("replied {id} {t}")),
                    _ => continue,
                };
                if let Ok(line) = line {
                    recorded.borrow_mut().push(line);
                }
            }
        });
        App { connection, proxy, signals }
    }

    async fn notify(&self, summary: &str, body: &str, actions: &[&str], hints: HashMap<&str, Value<'_>>) -> u32 {
        self.proxy.notify("Test App", 0, "dialog-information", summary, body, actions, hints, -1).await.unwrap()
    }

    async fn heard(&self, expected: &[&str]) {
        let start = Instant::now();
        loop {
            {
                let signals = self.signals.borrow();
                if signals.len() >= expected.len() {
                    assert_eq!(signals.as_slice(), expected);
                    return;
                }
            }
            assert!(start.elapsed() < common::TIMEOUT, "waiting for {expected:?}, got {:?}", self.signals.borrow());
            tokio::time::sleep(Duration::from_millis(2)).await;
        }
    }

    /// Nothing more arrives (for a while)
    async fn quiet(&self, count: usize) {
        tokio::time::sleep(Duration::from_millis(150)).await;
        assert_eq!(self.signals.borrow().len(), count, "{:?}", self.signals.borrow());
    }
}

#[test]
fn server_information_and_capabilities() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("info");
        let _service = service(&bus, &dir).await;
        let app = App::connect(&bus).await;
        let (name, vendor, _version, spec) = app.proxy.get_server_information().await.unwrap();
        assert_eq!((name.as_str(), vendor.as_str(), spec.as_str()), ("Maia", "Maia", "1.2"));
        let capabilities = app.proxy.get_capabilities().await.unwrap();
        for c in ["actions", "body", "body-markup", "body-hyperlinks", "persistence", "inline-reply", "inhibitions"] {
            assert!(capabilities.iter().any(|x| x == c), "{c} in {capabilities:?}");
        }
        assert!(capabilities.iter().any(|x| x == "sound"));
    });
}

#[test]
fn a_notification_reaches_the_shell_made_safe() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("reach");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let hints = HashMap::from([
            ("desktop-entry", Value::from("org.mozilla.firefox")),
            ("category", Value::from("transfer.complete")),
        ]);
        let id = app.notify("Download complete", "<b>photo.jpg</b> & <script>x()</script>done", &["default", "", "open", "Open"], hints).await;
        assert_ne!(id, 0);
        shell.wait("the notification", |s| s.notifications.contains_key(&id)).await;
        let shown = shell.shown(id).unwrap();
        assert_eq!(shown.app_name, "Test App");
        assert_eq!(shown.desktop_entry, "org.mozilla.firefox");
        assert_eq!(shown.app_icon, "dialog-information");
        assert_eq!(shown.body, "<b>photo.jpg</b> &amp; done");
        assert_eq!(shown.actions, [("default".to_string(), String::new()), ("open".to_string(), "Open".to_string())]);
        assert!(shown.popup && !shown.expired);
    });
}

#[test]
fn a_replacement_keeps_its_id_and_closing_tells_the_app() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("replace");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let id = app.notify("1 new message", "", &[], HashMap::new()).await;
        let again = app.proxy.notify("Test App", id, "", "2 new messages", "", &[], HashMap::new(), -1).await.unwrap();
        assert_eq!(again, id);
        shell.wait("the replacement", |s| s.notifications.get(&id).is_some_and(|n| n.summary == "2 new messages")).await;
        assert_eq!(shell.seen.borrow().notifications.len(), 1);

        app.proxy.close_notification(id).await.unwrap();
        app.heard(&[&format!("closed {id} 3")]).await;
        shell.wait("the removal", |s| s.notifications.is_empty()).await;
        // Closing what is gone is no error and says nothing
        app.proxy.close_notification(id).await.unwrap();
        app.quiet(1).await;
    });
}

#[test]
fn an_action_sends_the_token_first_then_the_action_then_closes() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("action");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let id = app.notify("Anna", "Hi", &["default", "", "mark-read", "Mark as read"], HashMap::new()).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&id)).await;

        assert_eq!(shell.invoke(id, "unknown", "").await, n::ErrorCode::InvalidArgument);
        assert_eq!(shell.invoke(id, "default", "token-1").await, n::ErrorCode::None);
        app.heard(&[&format!("token {id} token-1"), &format!("action {id} default"), &format!("closed {id} 2")]).await;
        shell.wait("the removal", |s| s.notifications.is_empty()).await;
        assert_eq!(shell.invoke(id, "default", "").await, n::ErrorCode::NotFound);
    });
}

#[test]
fn a_resident_notification_stays_after_an_action_and_no_token_means_no_token_signal() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("resident");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let hints = HashMap::from([("resident", Value::Bool(true))]);
        let id = app.notify("Music", "Song", &["pause", "Pause"], hints).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&id)).await;
        assert_eq!(shell.invoke(id, "pause", "").await, n::ErrorCode::None);
        app.heard(&[&format!("action {id} pause")]).await;
        app.quiet(1).await;
        assert!(shell.shown(id).is_some());
    });
}

#[test]
fn an_inline_reply_comes_back_as_notification_replied() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("reply");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let hints = HashMap::from([("x-kde-reply-placeholder-text", Value::from("Reply to Anna…"))]);
        let id = app.notify("Anna", "Lunch?", &["inline-reply", "Reply"], hints).await;
        shell.wait("the notification", |s| s.notifications.get(&id).is_some_and(|n| n.inline_reply && n.actions.is_empty())).await;
        assert_eq!(shell.reply(id, "Sure, at 12", "t").await, n::ErrorCode::None);
        app.heard(&[&format!("token {id} t"), &format!("replied {id} Sure, at 12"), &format!("closed {id} 2")]).await;
    });
}

#[test]
fn the_end_of_a_popup_keeps_it_in_the_list_and_closes_a_transient_one() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("expire");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let kept = app.notify("Mail", "", &[], HashMap::new()).await;
        let transient = app.notify("Volume", "", &[], HashMap::from([("transient", Value::Bool(true))])).await;
        shell.wait("both", |s| s.notifications.len() == 2).await;

        assert_eq!(shell.expire(kept).await, n::ErrorCode::None);
        shell.wait("expired", |s| s.notifications.get(&kept).is_some_and(|n| n.expired && !n.popup)).await;
        assert_eq!(shell.expire(transient).await, n::ErrorCode::None);
        app.heard(&[&format!("closed {transient} 1")]).await;
        shell.wait("the transient one gone", |s| s.notifications.len() == 1).await;

        assert_eq!(shell.dismiss(kept).await, n::ErrorCode::None);
        app.heard(&[&format!("closed {transient} 1"), &format!("closed {kept} 2")]).await;
    });
}

#[test]
fn signals_go_to_the_sender_only() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("private");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let sender = App::connect(&bus).await;
        let other = App::connect(&bus).await;
        let id = sender.notify("Your code", "123456", &["default", ""], HashMap::new()).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&id)).await;
        shell.invoke(id, "default", "").await;
        sender.heard(&[&format!("action {id} default"), &format!("closed {id} 2")]).await;
        other.quiet(0).await;
    });
}

#[test]
fn an_application_can_ask_for_quiet_until_it_leaves_the_bus() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("inhibit");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let presenter = App::connect(&bus).await;
        let app = App::connect(&bus).await;
        assert!(!app.proxy.inhibited().await.unwrap());

        let _cookie = presenter.proxy.inhibit("org.kde.impress", "Presenting", HashMap::new()).await.unwrap();
        shell.wait("quiet", |s| s.dnd_active && !s.dnd_enabled && s.inhibitors == ["Presenting"]).await;
        assert!(app.proxy.inhibited().await.unwrap());

        let normal = app.notify("Mail", "", &[], HashMap::new()).await;
        let critical = app.notify("Battery", "", &[], HashMap::from([("urgency", Value::U8(2))])).await;
        shell.wait("both", |s| s.notifications.len() == 2).await;
        assert!(!shell.shown(normal).unwrap().popup);
        assert!(shell.shown(critical).unwrap().popup);

        // The application leaves the bus (its recorder still holds a clone of the connection)
        presenter.connection.close().await.unwrap();
        shell.wait("the end of quiet", |s| !s.dnd_active && s.inhibitors.is_empty()).await;
        let start = Instant::now();
        while app.proxy.inhibited().await.unwrap() {
            assert!(start.elapsed() < common::TIMEOUT);
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    });
}

#[test]
fn uninhibit_ends_the_quiet() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("uninhibit");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let cookie = app.proxy.inhibit("org.kde.impress", "Presenting", HashMap::new()).await.unwrap();
        shell.wait("quiet", |s| s.dnd_active).await;
        app.proxy.un_inhibit(cookie).await.unwrap();
        shell.wait("no quiet", |s| !s.dnd_active).await;
    });
}

#[test]
fn pixels_become_a_small_png_file() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("pixels");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let (w, h) = (1600i32, 1200i32);
        let pixels: Vec<u8> = (0..w * h).flat_map(|i| [(i % 251) as u8, 80, 160, 255]).collect();
        let data = Value::from(
            zbus::zvariant::StructureBuilder::new()
                .add_field(w)
                .add_field(h)
                .add_field(w * 4)
                .add_field(true)
                .add_field(8i32)
                .add_field(4i32)
                .add_field(pixels)
                .build()
                .unwrap(),
        );
        let id = app.notify("Photo", "", &[], HashMap::from([("image-data", data)])).await;
        shell.wait("the image", |s| s.notifications.get(&id).is_some_and(|n| !n.image.is_empty())).await;
        let url = shell.shown(id).unwrap().image;
        let path = url.strip_prefix("file://").unwrap();
        assert!(path.starts_with(dir.0.to_str().unwrap()), "{path}");
        let reader = png::Decoder::new(std::io::BufReader::new(std::fs::File::open(path).unwrap())).read_info().unwrap();
        assert_eq!((reader.info().width, reader.info().height), (512, 384));

        // The file goes with the notification
        app.proxy.close_notification(id).await.unwrap();
        common::eventually("the file removed", || !std::path::Path::new(path).exists()).await;
    });
}

#[test]
fn a_second_server_does_not_take_the_name_from_the_first() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("name");
        let _first = service(&bus, &dir).await;
        let connection = bus.connect().await;
        assert!(!dbus::take_name(&connection).await.unwrap());
    });
}

#[test]
fn a_flood_is_answered_at_once_and_reaches_the_shell_in_few_batches() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("flood");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let app = App::connect(&bus).await;

        const COUNT: usize = 1000;
        let start = Instant::now();
        let calls = (0..COUNT).map(|i| {
            let proxy = app.proxy.clone();
            async move { proxy.notify("Flood", 0, "", &format!("message {i}"), "body", &[], HashMap::new(), -1).await.unwrap() }
        });
        let ids = futures::future::join_all(calls).await;
        let answered = start.elapsed();
        let mut unique = ids.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(unique.len(), COUNT);

        // The 200 newest, the older ones dropped
        let mut newest = ids.clone();
        newest.sort_unstable_by(|a, b| b.cmp(a));
        newest.truncate(MAX_NOTIFICATIONS);
        newest.sort_unstable();
        shell.wait("the 200 newest", |s| s.notifications.keys().copied().collect::<Vec<_>>() == newest).await;
        let shown = start.elapsed();
        let batches = shell.seen.borrow().batches;
        eprintln!("{COUNT} notifications: answered in {answered:?}, shown in {shown:?}, {batches} batches");
        // One batch per frame at most (plus the first one at once)
        let frames = (shown.as_millis() / 16) as u32 + 2;
        assert!(batches <= frames, "{batches} batches in {shown:?}");
        assert!(batches < COUNT as u32 / 10, "{batches} batches");
        assert_eq!(service.hub.borrow().store().len(), MAX_NOTIFICATIONS);
        // The dropped ones were closed with reason 4 (other)
        common::eventually("the dropped ones closed", || {
            app.signals.borrow().iter().filter(|s| s.ends_with(" 4")).count() == COUNT - MAX_NOTIFICATIONS
        })
        .await;
        drop(app.connection);
    });
}

/// An application the user turned off: Notify still answers with an id, the shell never sees the
/// notification, and the application hears that it is closed after it has the id
#[test]
fn a_turned_off_application_is_answered_and_closed_but_not_shown() {
    local(async {
        let bus = Bus::start();
        let dir = TempDir::new("dbus-turned-off");
        let service = service(&bus, &dir).await;
        let shell = Shell::connect(&service.hub).await;
        let settings = common::SettingsClient::connect(&service.hub).await;
        let app = App::connect(&bus).await;
        let first = app.notify("First", "", &[], HashMap::new()).await;
        shell.wait("the first", |s| s.notifications.contains_key(&first)).await;
        settings.wait("Test App listed", |s| s.apps.get("Test App").is_some_and(|a| a.sent)).await;

        assert_eq!(settings.set_app_enabled("Test App", false).await, n::ErrorCode::None);
        let second = app.notify("Second", "", &[], HashMap::new()).await;
        assert!(second != 0 && second != first);
        app.heard(&[&format!("closed {second} 4")]).await;
        assert!(!shell.seen.borrow().notifications.contains_key(&second));
        // What was in the list stays
        assert!(shell.seen.borrow().notifications.contains_key(&first));
    });
}
