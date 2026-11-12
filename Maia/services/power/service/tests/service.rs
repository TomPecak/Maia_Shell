//! The service over a real Cap'n Proto connection, with the fake backend (fake.rs) as the machine.
//!
//! Each test builds the service like main.rs does, connects a client through a socket pair, watches
//! the state and acts as the user and as the machine: it unplugs the charger, drains the battery,
//! moves the brightness, holds a profile.

mod common;

use std::time::Duration;

use tokio::sync::mpsc;

use maia_power::backend::{Commands, ErrorCode};
use maia_power::fake::{self, FakeAction, FakeHandle, Timing};
use maia_power::model::{Battery, BatteryState, Degradation, DeviceKind, WarningLevel};
use maia_power::power_capnp::{self as p, power_service};
use maia_power::rpc::{Hub, PowerService};

use common::{connect, local};

/// The service with the fake backend; the handle drives the simulated machine
fn start() -> (power_service::Client, FakeHandle) {
    let (events_tx, events_rx) = mpsc::unbounded_channel();
    let (commands, receiver) = Commands::single();
    let (handle, actions) = mpsc::unbounded_channel();
    let hub = Hub::new();
    tokio::task::spawn_local(Hub::run(hub.clone(), events_rx));
    tokio::task::spawn_local(fake::run(events_tx, receiver, actions, Timing::instant()));
    (PowerService::client(hub, commands, fake::NAME), handle)
}

#[test]
fn the_first_state_is_whole() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service.clone()).await;
        client.wait("the fake machine", |s| s.displays.contains_key(fake::PANEL) && s.active_profile.is_some()).await;
        // A later client gets everything at once
        let late = connect(service).await;
        late.wait("a snapshot", |s| s.snapshots == 1).await;
        let s = late.seen.borrow();
        assert!(s.on_battery);
        assert_eq!(s.summary_percentage, 80.0);
        assert_eq!(s.batteries.get(fake::BATTERY).map(|b| b.0), Some(p::DeviceKind::Battery));
        assert_eq!(s.batteries.get(fake::MOUSE).map(|b| b.0), Some(p::DeviceKind::Mouse));
        let (brightness, raw, max, minimum) = s.displays[fake::PANEL];
        assert_eq!((raw, max), (48000, 96000));
        assert!((brightness - 0.5).abs() < 1e-9 && minimum > 0.0);
        assert_eq!(s.keyboard, Some((true, 0.5)));
        assert_eq!(s.offered, [p::Profile::PowerSaver, p::Profile::Balanced, p::Profile::Performance]);
        assert_eq!(s.active_profile, Some(p::Profile::Balanced));
        assert!(s.events.is_empty(), "no events for the first state: {:?}", s.events);
    });
}

#[test]
fn the_info() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service).await;
        let reply = client.service.info_request().send().promise.await.unwrap();
        assert_eq!(reply.get().unwrap().get_backend().unwrap().to_str().unwrap(), "fake");
    });
}

#[test]
fn the_charger_and_a_draining_battery_give_events() {
    local(async {
        let (service, machine) = start();
        let client = connect(service).await;
        client.wait("the snapshot", |s| s.snapshots == 1 && s.summary_percentage == 80.0).await;

        machine.send(FakeAction::Charger(true)).unwrap();
        client.wait("on the charger", |s| !s.on_battery).await;
        machine.send(FakeAction::Charger(false)).unwrap();
        client.wait("on battery", |s| s.on_battery).await;
        for percentage in [30.0, 20.0, 12.0, 5.0, 2.0] {
            machine.send(FakeAction::Percentage(percentage)).unwrap();
        }
        client.wait("action level", |s| s.summary_level == Some(p::WarningLevel::Action)).await;
        machine.send(FakeAction::Charger(true)).unwrap();
        machine.send(FakeAction::Percentage(100.0)).unwrap();
        client.wait("full", |s| s.events.iter().any(|e| e.0 == p::EventKind::BatteryFull)).await;

        let kinds: Vec<p::EventKind> = client.seen.borrow().events.iter().map(|e| e.0).collect();
        assert_eq!(
            kinds,
            [
                p::EventKind::ChargerConnected,
                p::EventKind::ChargerDisconnected,
                p::EventKind::BatteryLow,
                p::EventKind::BatteryCritical,
                p::EventKind::BatteryAction,
                p::EventKind::ChargerConnected,
                p::EventKind::BatteryFull,
            ]
        );
    });
}

#[test]
fn brightness_from_the_slider_and_the_keys() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service).await;
        client.wait("the panel", |s| s.displays.contains_key(fake::PANEL)).await;

        // "" is the built-in panel
        assert_eq!(client.set_brightness("", 0.75).await, p::ErrorCode::None);
        client.wait("75 %", |s| s.displays[fake::PANEL].1 == 72000).await;
        assert_eq!(client.step_brightness(-2).await, p::ErrorCode::None);
        client.wait("65 %", |s| s.displays[fake::PANEL].1 == 62400).await;
        // Never off
        assert_eq!(client.set_brightness(fake::PANEL, 0.0).await, p::ErrorCode::None);
        client.wait("the minimum", |s| s.displays[fake::PANEL].1 == 1).await;
        assert_eq!(client.step_brightness(-1).await, p::ErrorCode::None);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(client.seen.borrow().displays[fake::PANEL].1, 1);

        assert_eq!(client.set_brightness("", 1.5).await, p::ErrorCode::InvalidArgument);
        assert_eq!(client.set_brightness("", f64::NAN).await, p::ErrorCode::InvalidArgument);
        assert_eq!(client.set_brightness("backlight:nothing", 0.5).await, p::ErrorCode::NotFound);
    });
}

#[test]
fn a_dragged_slider_ends_where_it_was_left() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service).await;
        client.wait("the panel", |s| s.displays.contains_key(fake::PANEL)).await;
        let mut answers = Vec::new();
        for i in 0..=20 {
            let mut request = client.control.set_brightness_request();
            request.get().set_brightness(i as f64 / 20.0);
            answers.push(request.send().promise);
        }
        for answer in answers {
            assert_eq!(answer.await.unwrap().get().unwrap().get_result().unwrap().get_error().unwrap(), p::ErrorCode::None);
        }
        client.wait("the last position", |s| s.displays[fake::PANEL].1 == 96000).await;
    });
}

#[test]
fn changes_from_outside_reach_the_clients() {
    local(async {
        let (service, machine) = start();
        let client = connect(service).await;
        client.wait("the panel", |s| s.displays.contains_key(fake::PANEL)).await;
        machine.send(FakeAction::ExternalBrightness(24000)).unwrap();
        client.wait("25 %", |s| s.displays[fake::PANEL].1 == 24000).await;
        machine.send(FakeAction::Degraded(Degradation::LapDetected)).unwrap();
        client.wait("on a lap", |s| s.degraded == Some(p::Degradation::LapDetected)).await;
    });
}

#[test]
fn devices_come_and_go_and_warn() {
    local(async {
        let (service, machine) = start();
        let client = connect(service).await;
        client.wait("the mouse", |s| s.batteries.contains_key(fake::MOUSE)).await;
        let headphones = |percentage: f64, level| Battery {
            id: "headset_dev_00_1B_66".into(),
            kind: DeviceKind::Headphones,
            present: true,
            power_supply: false,
            percentage,
            state: BatteryState::Discharging,
            warning_level: level,
            ..Battery::absent("headset_dev_00_1B_66")
        };
        machine.send(FakeAction::AddBattery(headphones(40.0, WarningLevel::None))).unwrap();
        client.wait("the headphones", |s| s.batteries.contains_key("headset_dev_00_1B_66")).await;
        machine.send(FakeAction::AddBattery(headphones(9.0, WarningLevel::Low))).unwrap();
        client.wait("a warning", |s| s.events.iter().any(|e| e.0 == p::EventKind::DeviceBatteryLow)).await;
        assert_eq!(client.seen.borrow().events.last().unwrap().1, "headset_dev_00_1B_66");
        machine.send(FakeAction::RemoveBattery("headset_dev_00_1B_66".into())).unwrap();
        client.wait("gone", |s| !s.batteries.contains_key("headset_dev_00_1B_66")).await;
    });
}

#[test]
fn the_keyboard_backlight() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service).await;
        client.wait("the keyboard", |s| s.keyboard.is_some()).await;
        assert_eq!(client.set_keyboard(1.0).await, p::ErrorCode::None);
        client.wait("bright", |s| s.keyboard == Some((true, 1.0))).await;
        assert_eq!(client.set_keyboard(0.0).await, p::ErrorCode::None);
        client.wait("off", |s| s.keyboard == Some((true, 0.0))).await;
        assert_eq!(client.set_keyboard(-0.1).await, p::ErrorCode::InvalidArgument);
    });
}

#[test]
fn profiles_and_holds() {
    local(async {
        let (service, _machine) = start();
        let client = connect(service).await;
        client.wait("the profiles", |s| s.active_profile.is_some()).await;

        assert_eq!(client.set_profile(p::Profile::Performance).await, p::ErrorCode::None);
        client.wait("performance", |s| s.active_profile == Some(p::Profile::Performance)).await;

        // A hold wins while it is held; dropping it gives the chosen profile back
        let (error, hold) = client.hold_profile(p::Profile::PowerSaver, "Presenting").await;
        assert_eq!(error, p::ErrorCode::None);
        client.wait("held", |s| s.active_profile == Some(p::Profile::PowerSaver) && s.holds == ["Presenting"]).await;
        drop(hold);
        client.wait("released", |s| s.active_profile == Some(p::Profile::Performance) && s.holds.is_empty()).await;

        // Choosing by hand releases every hold, as power-profiles-daemon does
        let (_, _kept) = client.hold_profile(p::Profile::PowerSaver, "Battery").await;
        client.wait("held again", |s| s.active_profile == Some(p::Profile::PowerSaver)).await;
        assert_eq!(client.set_profile(p::Profile::Balanced).await, p::ErrorCode::None);
        client.wait("chosen", |s| s.active_profile == Some(p::Profile::Balanced) && s.holds.is_empty()).await;
    });
}

#[test]
fn a_hold_ends_with_its_client() {
    local(async {
        let (service, _machine) = start();
        let watcher = connect(service.clone()).await;
        watcher.wait("the profiles", |s| s.active_profile.is_some()).await;
        {
            let holder = connect(service).await;
            let (_, _hold) = holder.hold_profile(p::Profile::Performance, "Compiling").await;
            watcher.wait("held", |s| s.active_profile == Some(p::Profile::Performance)).await;
            // The holder goes away with its hold still in its hands
        }
        watcher.wait("released", |s| s.active_profile == Some(p::Profile::Balanced) && s.holds.is_empty()).await;
    });
}

#[test]
fn refusals_reach_the_client() {
    local(async {
        let (service, machine) = start();
        let client = connect(service).await;
        client.wait("the panel", |s| s.displays.contains_key(fake::PANEL)).await;
        machine.send(FakeAction::Refuse(Some(ErrorCode::NotAllowed))).unwrap();
        tokio::time::sleep(Duration::from_millis(10)).await;
        assert_eq!(client.set_brightness("", 0.3).await, p::ErrorCode::NotAllowed);
        assert_eq!(client.set_profile(p::Profile::PowerSaver).await, p::ErrorCode::NotAllowed);
        let (error, _) = client.hold_profile(p::Profile::Performance, "x").await;
        assert_eq!(error, p::ErrorCode::NotAllowed);
    });
}
