//! UPower (system D-Bus): the batteries of the computer and of devices, the charger, the lid, the
//! keyboard backlight.
//!
//! How it follows UPower: it listens to every signal UPower sends (devices added and removed,
//! property changes, the keyboard's brightness) and, shortly after the first one of a burst
//! (`SETTLE`), reads everything again and sends what differs from what it sent before. UPower has a
//! handful of objects and answers GetAll in well under a millisecond, so reading all keeps this
//! simple and never out of step. When UPower is not there, the state says so; it is read as soon
//! as UPower starts.

use std::collections::BTreeMap;
use std::time::Duration;

use futures::StreamExt;
use tokio::sync::mpsc;
use zbus::zvariant::OwnedObjectPath;
use zbus::{Connection, MatchRule, MessageStream};

use super::dbus::{self, Props, bool_of, f64_of, i64_of, string_of, u32_of};
use crate::backend::{BackendEvent, Command, ErrorCode, OpError};
use crate::model::{Battery, BatteryState, DeviceKind, KeyboardBacklight, PowerStatus, WarningLevel, battery_icon};

pub const UPOWER: &str = "org.freedesktop.UPower";
const PATH: &str = "/org/freedesktop/UPower";
const DEVICE: &str = "org.freedesktop.UPower.Device";
const KBD_PATH: &str = "/org/freedesktop/UPower/KbdBacklight";
const KBD: &str = "org.freedesktop.UPower.KbdBacklight";

const SETTLE: Duration = Duration::from_millis(50);

/// The id of a device: the last part of its object path ("battery_BAT0")
pub fn device_id(path: &str) -> String {
    path.rsplit('/').next().unwrap_or(path).to_string()
}

/// A UPower device as a battery; None for what is not one (the charger, a monitor)
pub fn battery_from(id: &str, props: &Props) -> Option<Battery> {
    let kind = DeviceKind::from_upower(u32_of(props, "Type"))?;
    let percentage = f64_of(props, "Percentage");
    let state = BatteryState::from_upower(u32_of(props, "State"));
    let present = bool_of(props, "IsPresent");
    let mut icon_name = string_of(props, "IconName");
    if icon_name.is_empty() {
        icon_name = battery_icon(percentage, state, present);
    }
    Some(Battery {
        id: id.to_string(),
        kind,
        vendor: string_of(props, "Vendor"),
        model: string_of(props, "Model"),
        present,
        power_supply: bool_of(props, "PowerSupply"),
        percentage,
        state,
        warning_level: WarningLevel::from_upower(u32_of(props, "WarningLevel")),
        time_to_empty: i64_of(props, "TimeToEmpty"),
        time_to_full: i64_of(props, "TimeToFull"),
        energy_rate: f64_of(props, "EnergyRate"),
        capacity: f64_of(props, "Capacity"),
        icon_name,
    })
}

/// UPower's manager and its display device (all batteries of the computer as one)
pub fn status_from(manager: &Props, display_device: Option<&Props>) -> PowerStatus {
    let summary = display_device
        .and_then(|props| battery_from("DisplayDevice", props))
        .unwrap_or_else(|| Battery::absent("DisplayDevice"));
    PowerStatus {
        upower_available: true,
        on_battery: bool_of(manager, "OnBattery"),
        lid_present: bool_of(manager, "LidIsPresent"),
        lid_closed: bool_of(manager, "LidIsClosed"),
        summary,
    }
}

struct Source {
    conn: Connection,
    events: mpsc::UnboundedSender<BackendEvent>,
    sent_batteries: BTreeMap<String, Battery>,
    sent_status: Option<PowerStatus>,
    sent_keyboard: Option<KeyboardBacklight>,
}

impl Source {
    fn send(&self, event: BackendEvent) {
        let _ = self.events.send(event);
    }

    /// Reads everything and sends what changed
    async fn refresh(&mut self) {
        let (status, batteries, keyboard) = match read(&self.conn).await {
            Some(read) => read,
            None => (PowerStatus::unavailable(), BTreeMap::new(), KeyboardBacklight::unavailable()),
        };
        for id in self.sent_batteries.keys().filter(|id| !batteries.contains_key(*id)).cloned().collect::<Vec<_>>() {
            self.send(BackendEvent::BatteryRemoved(id));
        }
        for (id, battery) in &batteries {
            if self.sent_batteries.get(id) != Some(battery) {
                self.send(BackendEvent::Battery(battery.clone()));
            }
        }
        self.sent_batteries = batteries;
        if self.sent_status.as_ref() != Some(&status) {
            self.send(BackendEvent::Status(status.clone()));
            self.sent_status = Some(status);
        }
        if self.sent_keyboard.as_ref() != Some(&keyboard) {
            self.send(BackendEvent::Keyboard(keyboard.clone()));
            self.sent_keyboard = Some(keyboard);
        }
    }

    async fn command(&mut self, command: Command) {
        match command {
            Command::SetKeyboardBrightness { raw, reply } => {
                let result = dbus::call::<_, ()>(&self.conn, UPOWER, KBD_PATH, KBD, "SetBrightness", &(raw as i32))
                    .await
                    .map_err(|error| match &error {
                        zbus::Error::MethodError(name, _, _) if name.as_str().contains("AccessDenied") => {
                            OpError::new(ErrorCode::NotAllowed, error.to_string())
                        }
                        zbus::Error::MethodError(name, _, _) if name.as_str().contains("UnknownObject")
                            || name.as_str().contains("UnknownMethod") || name.as_str().contains("ServiceUnknown") =>
                        {
                            OpError::new(ErrorCode::NotSupported, error.to_string())
                        }
                        _ => OpError::new(ErrorCode::Failed, error.to_string()),
                    });
                let _ = reply.send(result);
                self.refresh().await;
            }
            other => tracing_unexpected(other),
        }
    }
}

fn tracing_unexpected(command: Command) {
    eprintln!("maia-power-service: upower got a command it does not handle: {command:?}");
}

/// Everything UPower knows now; None when it does not answer
async fn read(conn: &Connection) -> Option<(PowerStatus, BTreeMap<String, Battery>, KeyboardBacklight)> {
    let manager = dbus::get_all(conn, UPOWER, PATH, UPOWER).await.ok()?;
    let display_path: Option<OwnedObjectPath> =
        dbus::call(conn, UPOWER, PATH, UPOWER, "GetDisplayDevice", &()).await.ok();
    let display_props = match &display_path {
        Some(path) => dbus::get_all(conn, UPOWER, path.as_str(), DEVICE).await.ok(),
        None => None,
    };
    let status = status_from(&manager, display_props.as_ref());

    let mut batteries = BTreeMap::new();
    let devices: Vec<OwnedObjectPath> = dbus::call(conn, UPOWER, PATH, UPOWER, "EnumerateDevices", &()).await.unwrap_or_default();
    for path in dbus::paths(devices) {
        let Ok(props) = dbus::get_all(conn, UPOWER, &path, DEVICE).await else { continue };
        let id = device_id(&path);
        if let Some(battery) = battery_from(&id, &props) {
            batteries.insert(id, battery);
        }
    }

    let keyboard = match (
        dbus::call::<_, i32>(conn, UPOWER, KBD_PATH, KBD, "GetMaxBrightness", &()).await,
        dbus::call::<_, i32>(conn, UPOWER, KBD_PATH, KBD, "GetBrightness", &()).await,
    ) {
        (Ok(max), Ok(value)) if max > 0 => {
            KeyboardBacklight { available: true, raw: value.clamp(0, max) as u32, raw_max: max as u32 }
        }
        _ => KeyboardBacklight::unavailable(),
    };
    Some((status, batteries, keyboard))
}

/// Runs until the bus connection fails; commands: the keyboard backlight
pub async fn run(conn: Connection, events: mpsc::UnboundedSender<BackendEvent>, mut commands: mpsc::UnboundedReceiver<Command>) {
    let rule = match MatchRule::builder().msg_type(zbus::message::Type::Signal).sender(UPOWER) {
        Ok(builder) => builder.build(),
        Err(error) => return eprintln!("maia-power-service: upower: {error}"),
    };
    let owner_rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.DBus")
        .and_then(|b| b.interface("org.freedesktop.DBus"))
        .and_then(|b| b.member("NameOwnerChanged"))
        .and_then(|b| b.arg(0, UPOWER))
        .map(|b| b.build());
    let (Ok(mut signals), Ok(owner_rule)) = (MessageStream::for_match_rule(rule, &conn, Some(256)).await, owner_rule) else {
        eprintln!("maia-power-service: upower: cannot listen to UPower's signals");
        return;
    };
    let Ok(mut owner) = MessageStream::for_match_rule(owner_rule, &conn, None).await else { return };

    let mut source = Source { conn, events, sent_batteries: BTreeMap::new(), sent_status: None, sent_keyboard: None };
    source.refresh().await;
    let mut settle: Option<tokio::time::Instant> = None;
    loop {
        tokio::select! {
            Some(_) = signals.next() => {
                settle.get_or_insert(tokio::time::Instant::now() + SETTLE);
            }
            Some(_) = owner.next() => {
                settle.get_or_insert(tokio::time::Instant::now() + SETTLE);
            }
            _ = async { tokio::time::sleep_until(settle.unwrap()).await }, if settle.is_some() => {
                settle = None;
                source.refresh().await;
            }
            command = commands.recv() => match command {
                Some(command) => source.command(command).await,
                None => return,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::{OwnedValue, Str};

    fn props(values: &[(&str, OwnedValue)]) -> Props {
        values.iter().map(|(k, v)| (k.to_string(), v.try_clone().unwrap())).collect()
    }

    fn text(value: &str) -> OwnedValue {
        OwnedValue::from(Str::from(value.to_string()))
    }

    fn laptop_battery() -> Props {
        props(&[
            ("Type", OwnedValue::from(2u32)),
            ("PowerSupply", OwnedValue::from(true)),
            ("IsPresent", OwnedValue::from(true)),
            ("Percentage", OwnedValue::from(83.0f64)),
            ("State", OwnedValue::from(2u32)),
            ("WarningLevel", OwnedValue::from(1u32)),
            ("TimeToEmpty", OwnedValue::from(12600i64)),
            ("TimeToFull", OwnedValue::from(0i64)),
            ("EnergyRate", OwnedValue::from(6.8f64)),
            ("Capacity", OwnedValue::from(91.5f64)),
            ("Vendor", text("LGC")),
            ("Model", text("5B10W51867")),
            ("IconName", text("battery-level-80-symbolic")),
        ])
    }

    #[test]
    fn a_laptop_battery() {
        let b = battery_from("battery_BAT0", &laptop_battery()).unwrap();
        assert_eq!(b.kind, DeviceKind::Battery);
        assert!(b.power_supply && b.present);
        assert_eq!(b.state, BatteryState::Discharging);
        assert_eq!(b.warning_level, WarningLevel::None);
        assert_eq!(b.time_to_empty, 12600);
        assert_eq!((b.vendor.as_str(), b.model.as_str()), ("LGC", "5B10W51867"));
        assert_eq!(b.icon_name, "battery-level-80-symbolic");
        assert!((b.capacity - 91.5).abs() < 1e-9);
    }

    #[test]
    fn the_charger_is_not_a_battery() {
        let charger = props(&[("Type", OwnedValue::from(1u32)), ("Online", OwnedValue::from(true))]);
        assert_eq!(battery_from("line_power_AC", &charger), None);
    }

    #[test]
    fn a_mouse_without_an_icon_gets_one() {
        let mouse = props(&[
            ("Type", OwnedValue::from(5u32)),
            ("IsPresent", OwnedValue::from(true)),
            ("Percentage", OwnedValue::from(9.0f64)),
            ("State", OwnedValue::from(2u32)),
            ("WarningLevel", OwnedValue::from(3u32)),
        ]);
        let b = battery_from("mouse_x", &mouse).unwrap();
        assert_eq!(b.kind, DeviceKind::Mouse);
        assert!(!b.power_supply);
        assert_eq!(b.warning_level, WarningLevel::Low);
        assert_eq!(b.icon_name, "battery-level-10-symbolic");
    }

    #[test]
    fn status_with_and_without_a_battery() {
        let manager = props(&[
            ("OnBattery", OwnedValue::from(true)),
            ("LidIsPresent", OwnedValue::from(true)),
            ("LidIsClosed", OwnedValue::from(false)),
        ]);
        let status = status_from(&manager, Some(&laptop_battery()));
        assert!(status.upower_available && status.on_battery && status.lid_present && !status.lid_closed);
        assert_eq!(status.summary.id, "DisplayDevice");
        assert!((status.summary.percentage - 83.0).abs() < 1e-9);
        let desktop = status_from(&manager, None);
        assert!(!desktop.summary.present);
    }

    #[test]
    fn ids_from_paths() {
        assert_eq!(device_id("/org/freedesktop/UPower/devices/battery_BAT0"), "battery_BAT0");
        assert_eq!(device_id("DisplayDevice"), "DisplayDevice");
    }
}
