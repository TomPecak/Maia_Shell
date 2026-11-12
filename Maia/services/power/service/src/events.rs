//! Events for notifications, from two states one after the other (pure, tested without a clock).
//!
//! - The charger: when UPower's OnBattery changes.
//! - The computer's battery: when its warning level rises (low → critical → action), and once when it
//!   is full while charging. Falling back (charging again) gives no event: the next rise does.
//! - A device's battery: once when it reaches low (or lower).

use crate::model::{Battery, BatteryState, Event, EventKind, PowerStatus, WarningLevel};

pub fn status_events(old: &PowerStatus, new: &PowerStatus) -> Vec<Event> {
    let mut events = Vec::new();
    if !old.upower_available || !new.upower_available {
        // The first state of a source, or a source that went away: nothing changed for the user
        return events;
    }
    if old.on_battery != new.on_battery && new.summary.present {
        events.push(Event {
            kind: if new.on_battery { EventKind::ChargerDisconnected } else { EventKind::ChargerConnected },
            battery_id: String::new(),
            percentage: new.summary.percentage,
        });
    }
    let (before, after) = (&old.summary, &new.summary);
    if after.present && after.warning_level > before.warning_level {
        let kind = match after.warning_level {
            WarningLevel::Low => Some(EventKind::BatteryLow),
            WarningLevel::Critical => Some(EventKind::BatteryCritical),
            WarningLevel::Action => Some(EventKind::BatteryAction),
            WarningLevel::None => None,
        };
        if let Some(kind) = kind {
            events.push(Event { kind, battery_id: after.id.clone(), percentage: after.percentage });
        }
    }
    if after.present && after.state == BatteryState::Full && before.state != BatteryState::Full && !new.on_battery {
        events.push(Event { kind: EventKind::BatteryFull, battery_id: after.id.clone(), percentage: after.percentage });
    }
    events
}

/// A device's own battery (not the computer's: the summary tells about those)
pub fn battery_events(old: Option<&Battery>, new: &Battery) -> Vec<Event> {
    let Some(old) = old else { return Vec::new() };
    if new.power_supply || !new.present {
        return Vec::new();
    }
    if old.warning_level < WarningLevel::Low && new.warning_level >= WarningLevel::Low {
        return vec![Event { kind: EventKind::DeviceBatteryLow, battery_id: new.id.clone(), percentage: new.percentage }];
    }
    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::DeviceKind;

    fn summary(percentage: f64, state: BatteryState, level: WarningLevel) -> Battery {
        Battery {
            id: "DisplayDevice".into(),
            percentage,
            state,
            warning_level: level,
            present: true,
            ..Battery::absent("DisplayDevice")
        }
    }

    fn status(on_battery: bool, summary: Battery) -> PowerStatus {
        PowerStatus { upower_available: true, on_battery, lid_present: true, lid_closed: false, summary }
    }

    fn kinds(events: Vec<Event>) -> Vec<EventKind> {
        events.into_iter().map(|e| e.kind).collect()
    }

    #[test]
    fn the_charger() {
        let on_ac = status(false, summary(50.0, BatteryState::Charging, WarningLevel::None));
        let on_battery = status(true, summary(50.0, BatteryState::Discharging, WarningLevel::None));
        assert_eq!(kinds(status_events(&on_ac, &on_battery)), [EventKind::ChargerDisconnected]);
        assert_eq!(kinds(status_events(&on_battery, &on_ac)), [EventKind::ChargerConnected]);
        assert!(status_events(&on_ac, &on_ac).is_empty());
    }

    #[test]
    fn warning_levels_only_when_rising() {
        let none = status(true, summary(21.0, BatteryState::Discharging, WarningLevel::None));
        let low = status(true, summary(20.0, BatteryState::Discharging, WarningLevel::Low));
        let critical = status(true, summary(5.0, BatteryState::Discharging, WarningLevel::Critical));
        let action = status(true, summary(2.0, BatteryState::Discharging, WarningLevel::Action));
        assert_eq!(kinds(status_events(&none, &low)), [EventKind::BatteryLow]);
        assert!(status_events(&low, &low).is_empty());
        assert_eq!(kinds(status_events(&low, &critical)), [EventKind::BatteryCritical]);
        assert_eq!(kinds(status_events(&critical, &action)), [EventKind::BatteryAction]);
        // Plugged in: the level falls, nothing to say about the battery (the charger has its event)
        let charging = status(false, summary(5.0, BatteryState::Charging, WarningLevel::None));
        assert_eq!(kinds(status_events(&critical, &charging)), [EventKind::ChargerConnected]);
    }

    #[test]
    fn full_once_on_the_charger() {
        let charging = status(false, summary(99.0, BatteryState::Charging, WarningLevel::None));
        let full = status(false, summary(100.0, BatteryState::Full, WarningLevel::None));
        assert_eq!(kinds(status_events(&charging, &full)), [EventKind::BatteryFull]);
        assert!(status_events(&full, &full).is_empty());
    }

    #[test]
    fn nothing_from_a_source_that_appears_or_goes() {
        let unavailable = PowerStatus::unavailable();
        let low = status(true, summary(20.0, BatteryState::Discharging, WarningLevel::Low));
        assert!(status_events(&unavailable, &low).is_empty());
        assert!(status_events(&low, &unavailable).is_empty());
    }

    #[test]
    fn a_desktop_has_no_charger_events() {
        let mut before = status(false, Battery::absent("DisplayDevice"));
        before.summary.present = false;
        let mut after = before.clone();
        after.on_battery = true;
        assert!(status_events(&before, &after).is_empty());
    }

    #[test]
    fn a_mouse_running_low() {
        let mouse = |level| Battery {
            id: "mouse_1".into(),
            kind: DeviceKind::Mouse,
            power_supply: false,
            present: true,
            percentage: 10.0,
            warning_level: level,
            ..Battery::absent("mouse_1")
        };
        assert_eq!(kinds(battery_events(Some(&mouse(WarningLevel::None)), &mouse(WarningLevel::Low))),
                   [EventKind::DeviceBatteryLow]);
        assert!(battery_events(Some(&mouse(WarningLevel::Low)), &mouse(WarningLevel::Critical)).is_empty());
        assert!(battery_events(None, &mouse(WarningLevel::Low)).is_empty());
        // The computer's own batteries: the summary tells
        let mut laptop = mouse(WarningLevel::Low);
        laptop.power_supply = true;
        assert!(battery_events(Some(&mouse(WarningLevel::None)), &laptop).is_empty());
    }
}
