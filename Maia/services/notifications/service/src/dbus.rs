//! The D-Bus side: org.freedesktop.Notifications at /org/freedesktop/Notifications on the session
//! bus, for every existing application (the freedesktop.org Desktop Notifications specification
//! 1.2), with KDE's extensions on the same object:
//!
//! - inline replies: an action "inline-reply" becomes a text field, its text comes back with the
//!   signal NotificationReplied; hints x-kde-reply-placeholder-text, x-kde-reply-submit-button-text;
//! - Inhibit / UnInhibit and the property Inhibited: an application asks for quiet (a presentation);
//!   the inhibition ends when the application leaves the bus;
//! - hints x-kde-origin-name, x-kde-display-appname, x-kde-urls.
//!
//! zbus calls the methods from its own tasks, which must be Send; the hub is not (Cap'n Proto
//! objects live in it). So a method only hands a `DbusCall` to the hub's task (`run_calls`) and,
//! for Notify and Inhibit, awaits the answer, which comes within the same turn of the loop. Signals
//! go out in the order the hub decides them (`run_outgoing`), each to its sender only.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use futures::StreamExt;
use tokio::sync::{mpsc, oneshot};
use zbus::message::Header;
use zbus::names::BusName;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};

use crate::hub::{Hub, HubRef, Origin, Outgoing, SenderEvent};
use crate::markup;
use crate::model::{
    Action, ImageSource, Inhibitor, MAX_ACTIONS, MAX_BODY_CHARS, MAX_SUMMARY_CHARS, MAX_URLS, Pixels, Request, Urgency,
    limit_chars,
};

pub const NAME: &str = "org.freedesktop.Notifications";
pub const PATH: &str = "/org/freedesktop/Notifications";
pub const SPEC_VERSION: &str = "1.2";

/// A call of a D-Bus client, for the hub's task
#[derive(Debug)]
pub enum DbusCall {
    Notify { sender: String, replaces: u32, request: Request, reply: oneshot::Sender<u32> },
    Close { id: u32 },
    Inhibit { inhibitor: Inhibitor, reply: oneshot::Sender<u32> },
    UnInhibit { cookie: u32 },
    OwnerGone(String),
    // Jobs (dbus_jobs.rs)
    JobCreate { owner: String, request: crate::jobs::JobRequest, reply: oneshot::Sender<u32> },
    JobUpdate { id: u32, update: crate::jobs::JobUpdate },
    JobSetError { id: u32, code: u32 },
    JobTerminate { id: u32, code: u32, text: String },
}

pub struct Server {
    calls: mpsc::UnboundedSender<DbusCall>,
    inhibited: Arc<AtomicBool>,
}

fn sender_of(header: &Header<'_>) -> String {
    header.sender().map(|s| s.to_string()).unwrap_or_default()
}

fn gone() -> zbus::fdo::Error {
    zbus::fdo::Error::Failed("the notification service is ending".into())
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl Server {
    #[allow(clippy::too_many_arguments)]
    async fn notify(
        &self,
        #[zbus(header)] header: Header<'_>,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: Vec<String>,
        hints: HashMap<String, OwnedValue>,
        expire_timeout: i32,
    ) -> zbus::fdo::Result<u32> {
        let request = request_from(&app_name, &app_icon, &summary, &body, &actions, &hints, expire_timeout);
        let (reply, answer) = oneshot::channel();
        self.calls
            .send(DbusCall::Notify { sender: sender_of(&header), replaces: replaces_id, request, reply })
            .map_err(|_| gone())?;
        answer.await.map_err(|_| gone())
    }

    async fn close_notification(&self, id: u32) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::Close { id }).map_err(|_| gone())
    }

    fn get_capabilities(&self) -> Vec<String> {
        crate::CAPABILITIES.iter().map(|c| c.to_string()).collect()
    }

    #[zbus(out_args("name", "vendor", "version", "spec_version"))]
    fn get_server_information(&self) -> (String, String, String, String) {
        ("Maia".into(), "Maia".into(), env!("CARGO_PKG_VERSION").into(), SPEC_VERSION.into())
    }

    // --- KDE: inhibitions ---

    async fn inhibit(
        &self,
        #[zbus(header)] header: Header<'_>,
        desktop_entry: String,
        reason: String,
        _hints: HashMap<String, OwnedValue>,
    ) -> zbus::fdo::Result<u32> {
        let inhibitor = Inhibitor {
            app_name: desktop_entry.rsplit('.').next().unwrap_or_default().to_string(),
            desktop_entry: desktop_entry.trim_end_matches(".desktop").to_string(),
            reason,
            owner: sender_of(&header),
        };
        let (reply, answer) = oneshot::channel();
        self.calls.send(DbusCall::Inhibit { inhibitor, reply }).map_err(|_| gone())?;
        answer.await.map_err(|_| gone())
    }

    async fn un_inhibit(&self, cookie: u32) -> zbus::fdo::Result<()> {
        self.calls.send(DbusCall::UnInhibit { cookie }).map_err(|_| gone())
    }

    #[zbus(property)]
    fn inhibited(&self) -> bool {
        self.inhibited.load(Ordering::SeqCst)
    }

    // --- Signals ---

    #[zbus(signal)]
    async fn notification_closed(emitter: &SignalEmitter<'_>, id: u32, reason: u32) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn action_invoked(emitter: &SignalEmitter<'_>, id: u32, action_key: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn activation_token(emitter: &SignalEmitter<'_>, id: u32, activation_token: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn notification_replied(emitter: &SignalEmitter<'_>, id: u32, text: &str) -> zbus::Result<()>;
}

// --- Hints ---

fn str_hint(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    match hints.get(key).map(|v| &**v) {
        Some(Value::Str(s)) => Some(s.as_str().to_string()),
        Some(Value::ObjectPath(p)) => Some(p.as_str().to_string()),
        _ => None,
    }
}

fn int_hint(hints: &HashMap<String, OwnedValue>, key: &str) -> Option<i64> {
    match hints.get(key).map(|v| &**v) {
        Some(Value::U8(v)) => Some(*v as i64),
        Some(Value::I16(v)) => Some(*v as i64),
        Some(Value::U16(v)) => Some(*v as i64),
        Some(Value::I32(v)) => Some(*v as i64),
        Some(Value::U32(v)) => Some(*v as i64),
        Some(Value::I64(v)) => Some(*v),
        Some(Value::U64(v)) => Some(*v as i64),
        _ => None,
    }
}

/// Booleans arrive as booleans, and from some clients as numbers
fn bool_hint(hints: &HashMap<String, OwnedValue>, key: &str) -> bool {
    match hints.get(key).map(|v| &**v) {
        Some(Value::Bool(b)) => *b,
        _ => int_hint(hints, key).is_some_and(|v| v != 0),
    }
}

fn pixels_hint(hints: &HashMap<String, OwnedValue>) -> Option<Pixels> {
    // The name changed between versions of the specification
    let value = ["image-data", "image_data", "icon_data"].iter().find_map(|k| hints.get(*k))?;
    let value = value.try_clone().ok()?;
    let (width, height, rowstride, has_alpha, bits_per_sample, channels, data): (i32, i32, i32, bool, i32, i32, Vec<u8>) =
        value.try_into().ok()?;
    Some(Pixels { width, height, rowstride, has_alpha, bits_per_sample, channels, data })
}

fn strings_hint(hints: &HashMap<String, OwnedValue>, key: &str) -> Vec<String> {
    hints
        .get(key)
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| Vec::<String>::try_from(v).ok())
        .unwrap_or_default()
}

/// A Notify call in the service's terms: texts checked and cut, the body made safe, the image a URL
/// or pixels, KDE's inline reply taken out of the actions
pub fn request_from(
    app_name: &str,
    app_icon: &str,
    summary: &str,
    body: &str,
    actions: &[String],
    hints: &HashMap<String, OwnedValue>,
    timeout: i32,
) -> Request {
    let mut list = Vec::new();
    let mut inline_reply = false;
    let mut reply_label = String::new();
    for pair in actions.chunks_exact(2) {
        let (key, label) = (pair[0].trim(), pair[1].trim());
        if key.is_empty() {
            continue;
        }
        if key == "inline-reply" {
            inline_reply = true;
            reply_label = label.to_string();
        } else if list.len() < MAX_ACTIONS {
            list.push(Action { key: key.to_string(), label: label.to_string() });
        }
    }

    let image = match pixels_hint(hints) {
        Some(pixels) => ImageSource::Pixels(pixels),
        None => {
            let url = ["image-path", "image_path"]
                .iter()
                .find_map(|k| str_hint(hints, k))
                .map(|p| crate::image::url_from_path(&p))
                .unwrap_or_default();
            if url.is_empty() { ImageSource::None } else { ImageSource::Url(url) }
        }
    };
    // An image path may also be an icon name; an app icon that is a path is a URL
    let mut app_icon = crate::image::icon(app_icon);
    if app_icon.is_empty() {
        if let Some(name) = str_hint(hints, "image-path").filter(|p| !p.contains('/')) {
            app_icon = name;
        }
    }

    let display_name = str_hint(hints, "x-kde-display-appname").filter(|n| !n.is_empty());
    let mut urls: Vec<String> = strings_hint(hints, "x-kde-urls");
    urls.truncate(MAX_URLS);

    Request {
        app_name: display_name.unwrap_or_else(|| app_name.to_string()),
        desktop_entry: str_hint(hints, "desktop-entry").unwrap_or_default().trim_end_matches(".desktop").to_string(),
        app_icon,
        summary: limit_chars(markup::plain(summary), MAX_SUMMARY_CHARS),
        body: markup::sanitize(&limit_chars(body.to_string(), MAX_BODY_CHARS)),
        image,
        actions: list,
        action_icons: bool_hint(hints, "action-icons"),
        urgency: int_hint(hints, "urgency").map(Urgency::from_level).unwrap_or_default(),
        category: str_hint(hints, "category").unwrap_or_default(),
        timeout: timeout.max(-1),
        transient: bool_hint(hints, "transient"),
        resident: bool_hint(hints, "resident"),
        inline_reply,
        reply_placeholder: str_hint(hints, "x-kde-reply-placeholder-text").unwrap_or_default(),
        reply_submit_text: str_hint(hints, "x-kde-reply-submit-button-text").unwrap_or(reply_label),
        origin_name: str_hint(hints, "x-kde-origin-name").unwrap_or_default(),
        urls,
        sound_name: str_hint(hints, "sound-name").unwrap_or_default(),
        sound_file: str_hint(hints, "sound-file").map(|f| crate::image::url_from_path(&f)).unwrap_or_default(),
        suppress_sound: bool_hint(hints, "suppress-sound"),
    }
}

// --- Running ---

/// Serves the interface at PATH on `connection` and connects it to the hub (the bus name is taken
/// separately, `take_name`); everything runs in the background of the current LocalSet
pub async fn serve(connection: &zbus::Connection, hub: &HubRef) -> zbus::Result<()> {
    let (calls, call_receiver) = mpsc::unbounded_channel();
    let (out, out_receiver) = mpsc::unbounded_channel();
    let inhibited = hub.borrow().inhibited_flag();
    connection.object_server().at(PATH, Server { calls: calls.clone(), inhibited }).await?;
    crate::dbus_jobs::serve(connection, calls.clone()).await?;
    hub.borrow_mut().set_dbus_out(out);
    tokio::task::spawn_local(run_calls(hub.clone(), call_receiver));
    tokio::task::spawn_local(run_outgoing(connection.clone(), out_receiver));
    tokio::task::spawn_local(watch_owners(connection.clone(), calls));
    Ok(())
}

/// Takes org.freedesktop.Notifications, replacing another server that allows it. False when another
/// server keeps it (Maia's programs are still served over Cap'n Proto).
pub async fn take_name(connection: &zbus::Connection) -> zbus::Result<bool> {
    take(connection, NAME).await
}

/// Takes the names of the job server (org.kde.JobViewServer, org.kde.kuiserver); false when another
/// server keeps them
pub async fn take_job_names(connection: &zbus::Connection) -> zbus::Result<bool> {
    let mut all = true;
    for name in crate::dbus_jobs::NAMES {
        all &= take(connection, name).await?;
    }
    Ok(all)
}

async fn take(connection: &zbus::Connection, name: &'static str) -> zbus::Result<bool> {
    use zbus::fdo::{RequestNameFlags, RequestNameReply};
    let flags = RequestNameFlags::ReplaceExisting | RequestNameFlags::DoNotQueue;
    match connection.request_name_with_flags(name, flags).await {
        Ok(RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner) => Ok(true),
        Ok(_) => Ok(false),
        Err(zbus::Error::NameTaken) => Ok(false),
        Err(error) => Err(error),
    }
}

async fn run_calls(hub: HubRef, mut calls: mpsc::UnboundedReceiver<DbusCall>) {
    while let Some(call) = calls.recv().await {
        match call {
            DbusCall::Notify { sender, replaces, request, reply } => {
                let origin = if sender.is_empty() { Origin::Nobody } else { Origin::DBus(sender) };
                let _ = reply.send(Hub::notify(&hub, replaces, request, origin));
            }
            DbusCall::Close { id } => {
                Hub::close_by_app(&hub, id);
            }
            DbusCall::Inhibit { inhibitor, reply } => {
                let _ = reply.send(Hub::inhibit(&hub, inhibitor));
            }
            DbusCall::UnInhibit { cookie } => Hub::uninhibit(&hub, cookie),
            DbusCall::OwnerGone(name) => Hub::owner_gone(&hub, &name),
            DbusCall::JobCreate { owner, request, reply } => {
                let _ = reply.send(Hub::create_job(&hub, &owner, request));
            }
            DbusCall::JobUpdate { id, update } => Hub::update_job(&hub, id, update),
            DbusCall::JobSetError { id, code } => Hub::set_job_error(&hub, id, code),
            DbusCall::JobTerminate { id, code, text } => Hub::terminate_job(&hub, id, code, &text),
        }
    }
}

/// Sends the hub's signals in its order, each to its sender only
async fn run_outgoing(connection: zbus::Connection, mut out: mpsc::UnboundedReceiver<Outgoing>) {
    while let Some(outgoing) = out.recv().await {
        let result = match outgoing {
            Outgoing::Signal { destination, id, event } => emit(&connection, &destination, id, event).await,
            Outgoing::InhibitedChanged => match connection.object_server().interface::<_, Server>(PATH).await {
                Ok(iface) => iface.get().await.inhibited_changed(iface.signal_emitter()).await,
                Err(error) => Err(error),
            },
            Outgoing::JobRequest { id, kind } => crate::dbus_jobs::emit(&connection, id, kind).await,
            Outgoing::JobGone(id) => {
                crate::dbus_jobs::remove(&connection, id).await;
                Ok(())
            }
        };
        if let Err(error) = result {
            // A sender that left the bus cannot be told; nothing else to do
            if !matches!(error, zbus::Error::MethodError(..)) {
                eprintln!("maia-notifications-service: D-Bus signal: {error}");
            }
        }
    }
}

async fn emit(connection: &zbus::Connection, destination: &str, id: u32, event: SenderEvent) -> zbus::Result<()> {
    let destination = BusName::try_from(destination)?;
    let emitter = SignalEmitter::new(connection, PATH)?.set_destination(destination);
    match event {
        SenderEvent::ActionInvoked { key, token } => {
            if !token.is_empty() {
                Server::activation_token(&emitter, id, &token).await?;
            }
            Server::action_invoked(&emitter, id, &key).await
        }
        SenderEvent::Replied { text, token } => {
            if !token.is_empty() {
                Server::activation_token(&emitter, id, &token).await?;
            }
            Server::notification_replied(&emitter, id, &text).await
        }
        SenderEvent::Closed(reason) => Server::notification_closed(&emitter, id, reason.dbus_code()).await,
    }
}

/// Clients that leave the bus: their inhibitions end
async fn watch_owners(connection: zbus::Connection, calls: mpsc::UnboundedSender<DbusCall>) {
    let Ok(proxy) = zbus::fdo::DBusProxy::new(&connection).await else { return };
    let Ok(mut changes) = proxy.receive_name_owner_changed().await else { return };
    while let Some(change) = changes.next().await {
        let Ok(args) = change.args() else { continue };
        if args.new_owner().is_none() && args.name().starts_with(':') && calls.send(DbusCall::OwnerGone(args.name().to_string())).is_err() {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hints(pairs: &[(&str, Value<'static>)]) -> HashMap<String, OwnedValue> {
        pairs.iter().map(|(k, v)| (k.to_string(), OwnedValue::try_from(v.clone()).unwrap())).collect()
    }

    #[test]
    fn hints_of_a_mail_client() {
        let h = hints(&[
            ("urgency", Value::U8(2)),
            ("category", Value::from("email.arrived")),
            ("desktop-entry", Value::from("org.mozilla.Thunderbird.desktop")),
            ("sound-name", Value::from("message-new-email")),
            ("resident", Value::Bool(true)),
            ("transient", Value::I32(1)),
        ]);
        let r = request_from("Thunderbird", "mail-unread", "New mail\nfrom Anna", "Hi & <b>bye</b>", &[], &h, 5000);
        assert_eq!(r.urgency, Urgency::Critical);
        assert_eq!(r.category, "email.arrived");
        assert_eq!(r.desktop_entry, "org.mozilla.Thunderbird");
        assert_eq!(r.summary, "New mail from Anna");
        assert_eq!(r.body, "Hi &amp; <b>bye</b>");
        assert_eq!(r.app_icon, "mail-unread");
        assert_eq!(r.sound_name, "message-new-email");
        assert!(r.resident && r.transient);
        assert_eq!(r.timeout, 5000);
    }

    #[test]
    fn actions_come_in_pairs_and_inline_reply_becomes_a_field() {
        let actions: Vec<String> = ["default", "", "mark-read", "Mark as read", "inline-reply", "Reply", "odd"].iter().map(|s| s.to_string()).collect();
        let h = hints(&[("x-kde-reply-placeholder-text", Value::from("Reply to Anna…"))]);
        let r = request_from("Chat", "", "Anna", "Hi", &actions, &h, -1);
        assert_eq!(r.actions.iter().map(|a| a.key.as_str()).collect::<Vec<_>>(), ["default", "mark-read"]);
        assert!(r.inline_reply);
        assert_eq!(r.reply_placeholder, "Reply to Anna…");
        assert_eq!(r.reply_submit_text, "Reply");
    }

    #[test]
    fn images_from_paths_and_from_pixels() {
        let h = hints(&[("image-path", Value::from("/tmp/shot.png"))]);
        assert_eq!(request_from("a", "", "s", "", &[], &h, -1).image, ImageSource::Url("file:///tmp/shot.png".into()));
        // An image path without a slash is an icon name
        let h = hints(&[("image-path", Value::from("camera-photo"))]);
        let r = request_from("a", "", "s", "", &[], &h, -1);
        assert_eq!((r.image, r.app_icon.as_str()), (ImageSource::None, "camera-photo"));

        let data = Value::from(zbus::zvariant::StructureBuilder::new()
            .add_field(2i32).add_field(1i32).add_field(8i32).add_field(true).add_field(8i32).add_field(4i32)
            .add_field(vec![1u8, 2, 3, 4, 5, 6, 7, 8])
            .build().unwrap());
        let h = hints(&[("image-data", data)]);
        match request_from("a", "", "s", "", &[], &h, -1).image {
            ImageSource::Pixels(p) => assert_eq!((p.width, p.height, p.channels, p.data.len()), (2, 1, 4, 8)),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn kde_hints() {
        let urls = Value::from(vec!["file:///home/a/shot.png".to_string()]);
        let h = hints(&[
            ("x-kde-display-appname", Value::from("Spectacle")),
            ("x-kde-origin-name", Value::from("Pixel 7")),
            ("x-kde-urls", urls),
        ]);
        let r = request_from("spectacle", "", "Screenshot saved", "", &[], &h, -1);
        assert_eq!(r.app_name, "Spectacle");
        assert_eq!(r.origin_name, "Pixel 7");
        assert_eq!(r.urls, ["file:///home/a/shot.png"]);
    }

    #[test]
    fn long_texts_are_cut() {
        let summary = "x".repeat(1000);
        let r = request_from("a", "", &summary, "", &[], &HashMap::new(), -7);
        assert_eq!(r.summary.chars().count(), MAX_SUMMARY_CHARS + 1);
        assert_eq!(r.timeout, -1);
    }
}
