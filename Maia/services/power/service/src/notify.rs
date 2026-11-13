//! The battery warnings as notifications: the power service knows when a battery runs low, so it
//! says so itself, as a client of the notification service (its Notifier, Cap'n Proto). A shell
//! shows the notification like any other; nothing in a shell turns power events into texts.
//!
//! One notification per subject, replaced as the state goes on: the computer's battery (low, then
//! critical, then empty: the same notification), each device's battery, and "charged". The charger
//! takes the battery warning away; unplugging it takes "charged" away.
//!
//! The notification service is a weak dependency: without it (not started yet, restarting) a
//! warning is dropped after a short try, and the power service goes on. Nothing here makes the hub
//! wait: events come through a channel, the calls are awaited in this task.

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;

use capnp_rpc::{RpcSystem, rpc_twoparty_capnp, twoparty};
use futures::AsyncReadExt;
use tokio::sync::mpsc;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::model::{Battery, DeviceKind, Event, EventKind};
use crate::notifications_capnp as n;

/// How long one attempt to reach the notification service may take
const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);

/// What a notification is about: each subject has at most one notification at a time
#[derive(Clone, Debug, Hash, PartialEq, Eq)]
pub enum Subject {
    /// The computer's battery (low, critical, empty)
    Battery,
    /// A device's battery, by its id
    Device(String),
    /// The computer's battery is charged
    Charged,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Urgency {
    Low,
    Normal,
    Critical,
}

/// A notification of the power service
#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub summary: String,
    pub body: String,
    pub icon: &'static str,
    pub urgency: Urgency,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Notice {
    Show(Subject, Message),
    Close(Subject),
}

fn device_name(battery: Option<&Battery>) -> String {
    let Some(battery) = battery else { return "Device".into() };
    if !battery.model.is_empty() {
        return battery.model.clone();
    }
    match battery.kind {
        DeviceKind::Mouse => "Mouse",
        DeviceKind::Keyboard => "Keyboard",
        DeviceKind::Touchpad => "Touchpad",
        DeviceKind::GamingInput => "Game controller",
        DeviceKind::Pen => "Pen",
        DeviceKind::Headset => "Headset",
        DeviceKind::Headphones => "Headphones",
        DeviceKind::Speakers => "Speaker",
        DeviceKind::Phone => "Phone",
        DeviceKind::Tablet => "Tablet",
        _ => "Device",
    }
    .into()
}

/// What an event of the hub means for the notifications (none for most); `battery` is the battery
/// the event is about, when the hub knows it
pub fn notice_for(event: &Event, battery: Option<&Battery>) -> Vec<Notice> {
    let percent = event.percentage.round() as i64;
    let show = |subject, summary: String, body: String, icon, urgency| {
        vec![Notice::Show(subject, Message { summary, body, icon, urgency })]
    };
    match event.kind {
        EventKind::BatteryLow => show(
            Subject::Battery,
            "Battery low".into(),
            format!("{percent} % left. Connect the charger."),
            "battery-low-symbolic",
            Urgency::Normal,
        ),
        EventKind::BatteryCritical => show(
            Subject::Battery,
            "Battery critically low".into(),
            format!("{percent} % left. Connect the charger now."),
            "battery-caution-symbolic",
            Urgency::Critical,
        ),
        EventKind::BatteryAction => show(
            Subject::Battery,
            "Battery empty".into(),
            "The computer will turn off soon to keep your work safe.".into(),
            "battery-caution-symbolic",
            Urgency::Critical,
        ),
        EventKind::DeviceBatteryLow => show(
            Subject::Device(event.battery_id.clone()),
            format!("{} battery low", device_name(battery)),
            format!("{percent} % left."),
            "battery-low-symbolic",
            Urgency::Normal,
        ),
        // Into the list only: good news needs no popup
        EventKind::BatteryFull => show(
            Subject::Charged,
            "Battery charged".into(),
            "You can unplug the charger.".into(),
            "battery-full-charged-symbolic",
            Urgency::Low,
        ),
        EventKind::ChargerConnected => vec![Notice::Close(Subject::Battery)],
        EventKind::ChargerDisconnected => vec![Notice::Close(Subject::Charged)],
    }
}

/// $MAIA_NOTIFICATIONS_SOCKET, or $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock (the
/// notification service's rule)
pub fn socket_path() -> PathBuf {
    if let Some(path) = std::env::var_os("MAIA_NOTIFICATIONS_SOCKET") {
        return PathBuf::from(path);
    }
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "wayland-0".into());
    let display = display.rsplit('/').next().unwrap_or("wayland-0").to_string();
    runtime.join("maia").join(format!("notifications-{display}.sock"))
}

async fn connect(socket: &PathBuf) -> Option<n::notifier::Client> {
    let stream = tokio::time::timeout(CONNECT_TIMEOUT, tokio::net::UnixStream::connect(socket)).await.ok()?.ok()?;
    let (reader, writer) = stream.compat().split();
    let network = Box::new(twoparty::VatNetwork::new(
        futures::io::BufReader::new(reader),
        futures::io::BufWriter::new(writer),
        rpc_twoparty_capnp::Side::Client,
        Default::default(),
    ));
    let mut rpc_system = RpcSystem::new(network, None);
    let notifier: n::notifier::Client = rpc_system.bootstrap(rpc_twoparty_capnp::Side::Server);
    tokio::task::spawn_local(async move {
        let _ = rpc_system.await;
    });
    Some(notifier)
}

fn fill(mut r: n::notification_request::Builder, message: &Message) {
    r.set_app_name("Power");
    r.set_desktop_entry("org.maia.settings");
    r.set_app_icon(message.icon);
    r.set_summary(&message.summary);
    r.set_body(&message.body);
    r.set_urgency(match message.urgency {
        Urgency::Low => n::Urgency::Low,
        Urgency::Normal => n::Urgency::Normal,
        Urgency::Critical => n::Urgency::Critical,
    });
    r.set_category("device");
    r.set_timeout(-1);
}

struct Sender {
    socket: PathBuf,
    notifier: Option<n::notifier::Client>,
    shown: HashMap<Subject, n::notification_handle::Client>,
    warned: bool,
}

impl Sender {
    async fn notifier(&mut self) -> Option<n::notifier::Client> {
        if self.notifier.is_none() {
            self.notifier = connect(&self.socket).await;
            if self.notifier.is_none() && !self.warned {
                eprintln!("maia-power-service: no notification service at {}", self.socket.display());
                self.warned = true;
            }
        }
        self.notifier.clone()
    }

    /// The connection failed: everything of it is gone (the service lost its list too)
    fn lost(&mut self) {
        self.notifier = None;
        self.shown.clear();
    }

    async fn show(&mut self, subject: Subject, message: &Message) {
        // The same subject: its notification is replaced, unless the user has closed it meanwhile
        if let Some(handle) = self.shown.get(&subject) {
            let mut request = handle.update_request();
            fill(request.get().init_notification(), message);
            match request.send().promise.await {
                Ok(reply) => {
                    let ok = reply
                        .get()
                        .and_then(|r| r.get_result())
                        .and_then(|r| Ok(r.get_error()?))
                        .is_ok_and(|e| e == n::ErrorCode::None);
                    if ok {
                        return;
                    }
                    self.shown.remove(&subject);
                }
                Err(_) => self.lost(),
            }
        }
        for _attempt in 0..2 {
            let Some(notifier) = self.notifier().await else { return };
            let mut request = notifier.notify_request();
            fill(request.get().init_notification(), message);
            match request.send().promise.await {
                Ok(reply) => {
                    if let Ok(handle) = reply.get().and_then(|r| r.get_handle()) {
                        self.shown.insert(subject, handle);
                    }
                    return;
                }
                // A connection that broke since the last time: once more with a new one
                Err(_) => self.lost(),
            }
        }
    }

    async fn close(&mut self, subject: &Subject) {
        if let Some(handle) = self.shown.remove(subject) {
            if handle.close_request().send().promise.await.is_err() {
                self.lost();
            }
        }
    }
}

/// Turns the hub's events into notifications until the hub ends
pub async fn run(mut events: mpsc::UnboundedReceiver<(Event, Option<Battery>)>, socket: PathBuf) {
    let mut sender = Sender { socket, notifier: None, shown: HashMap::new(), warned: false };
    while let Some((event, battery)) = events.recv().await {
        for notice in notice_for(&event, battery.as_ref()) {
            match notice {
                Notice::Show(subject, message) => sender.show(subject, &message).await,
                Notice::Close(subject) => sender.close(&subject).await,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(kind: EventKind, percentage: f64) -> Event {
        Event { kind, battery_id: "battery_BAT0".into(), percentage }
    }

    #[test]
    fn the_computers_battery_is_one_notification_that_gets_more_urgent() {
        let low = notice_for(&event(EventKind::BatteryLow, 9.6), None);
        let critical = notice_for(&event(EventKind::BatteryCritical, 4.2), None);
        match (&low[..], &critical[..]) {
            ([Notice::Show(a, low)], [Notice::Show(b, critical)]) => {
                assert_eq!((a, b), (&Subject::Battery, &Subject::Battery));
                assert_eq!(low.body, "10 % left. Connect the charger.");
                assert_eq!(low.urgency, Urgency::Normal);
                assert_eq!(critical.summary, "Battery critically low");
                assert_eq!(critical.urgency, Urgency::Critical);
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn the_charger_takes_the_warning_away_and_unplugging_takes_charged_away() {
        assert_eq!(notice_for(&event(EventKind::ChargerConnected, 50.0), None), [Notice::Close(Subject::Battery)]);
        assert_eq!(notice_for(&event(EventKind::ChargerDisconnected, 50.0), None), [Notice::Close(Subject::Charged)]);
        match &notice_for(&event(EventKind::BatteryFull, 100.0), None)[..] {
            [Notice::Show(Subject::Charged, m)] => assert_eq!(m.urgency, Urgency::Low),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn devices_are_named_by_their_model_or_their_kind() {
        let mut mouse = Battery::absent("mouse_1");
        mouse.kind = DeviceKind::Mouse;
        let e = Event { kind: EventKind::DeviceBatteryLow, battery_id: "mouse_1".into(), percentage: 8.0 };
        match &notice_for(&e, Some(&mouse))[..] {
            [Notice::Show(Subject::Device(id), m)] => {
                assert_eq!(id, "mouse_1");
                assert_eq!(m.summary, "Mouse battery low");
            }
            other => panic!("{other:?}"),
        }
        mouse.model = "MX Master 3".into();
        match &notice_for(&e, Some(&mouse))[..] {
            [Notice::Show(_, m)] => assert_eq!(m.summary, "MX Master 3 battery low"),
            other => panic!("{other:?}"),
        }
    }
}
