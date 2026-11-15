//! The settings door (NotificationSettings, Maia Settings) over real Cap'n Proto connections: the
//! applications that send, turning one off, the lock screen's flag reaching the shells, and the
//! settings kept on disk across a restart of the service.

mod common;

use std::rc::Rc;
use std::time::Duration;

use common::{Sender, SettingsClient, Shell, TempDir, local};
use maia_notifications::hub::{Hub, HubRef, SETTINGS_SAVE_DELAY};
use maia_notifications::model::now_ms;
use maia_notifications::notifications_capnp::{self as n, center_listener, notification_center};
use maia_notifications::settings::FILE_NAME;

fn send_as(desktop_entry: &'static str, name: &'static str, summary: &'static str) -> impl FnOnce(n::notification_request::Builder) {
    move |mut r| {
        r.set_app_name(name);
        r.set_desktop_entry(desktop_entry);
        r.set_app_icon("mail-unread");
        r.set_summary(summary);
    }
}

/// A hub whose settings live in `dir`, with `data` as the only data directory
fn hub_with_settings(dir: &TempDir) -> HubRef {
    let hub = common::hub(dir);
    Hub::load_settings(&hub, dir.0.join(FILE_NAME), vec![dir.0.join("data")]);
    hub
}

#[test]
fn a_sender_is_listed_and_once_turned_off_it_is_not_shown() {
    local(async {
        let dir = TempDir::new("settings-off");
        let hub = hub_with_settings(&dir);
        let shell = Shell::connect(&hub).await;
        let settings = SettingsClient::connect(&hub).await;
        let sender = Sender::connect(&hub).await;

        let first = sender.send(send_as("org.maia.mail.desktop", "Mail", "Hello")).await;
        shell.wait("the first", |s| s.notifications.contains_key(&first.id)).await;
        settings.wait("Mail listed", |s| s.apps.contains_key("org.maia.mail")).await;
        let app = settings.seen.borrow().apps["org.maia.mail"].clone();
        assert_eq!((app.app_name.as_str(), app.desktop_entry.as_str(), app.app_icon.as_str()), ("Mail", "org.maia.mail", "mail-unread"));
        assert!(app.enabled && app.sent && !app.declared);

        assert_eq!(settings.set_app_enabled("org.maia.mail", false).await, n::ErrorCode::None);
        settings.wait("Mail off", |s| !s.apps["org.maia.mail"].enabled).await;
        let second = sender.send(send_as("org.maia.mail", "Mail", "Again")).await;
        assert!(second.id != 0 && second.id != first.id);
        second.hear("closed Other").await;
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(!shell.seen.borrow().notifications.contains_key(&second.id), "a turned off application is not shown");
        // Another application is not touched
        let other = sender.send(send_as("", "notify-send", "Other")).await;
        shell.wait("the other", |s| s.notifications.contains_key(&other.id)).await;

        assert_eq!(settings.set_app_enabled("org.maia.mail", true).await, n::ErrorCode::None);
        let third = sender.send(send_as("org.maia.mail", "Mail", "Back")).await;
        shell.wait("on again", |s| s.notifications.contains_key(&third.id)).await;
        assert_eq!(settings.set_app_enabled("nobody", false).await, n::ErrorCode::NotFound);
    });
}

#[test]
fn the_lock_screens_flag_reaches_the_shells() {
    local(async {
        let dir = TempDir::new("settings-lock");
        let hub = hub_with_settings(&dir);
        let shell = Shell::connect(&hub).await;
        let settings = SettingsClient::connect(&hub).await;
        shell.wait("the snapshot", |s| s.lock_screen_notifications == Some(true)).await;
        assert!(settings.seen.borrow().lock_screen_notifications);

        settings.set_lock_screen_notifications(false).await;
        shell.wait("off for the shell", |s| s.lock_screen_notifications == Some(false)).await;
        settings.wait("off for the settings", |s| !s.lock_screen_notifications).await;
        // A shell that comes later finds it in its snapshot
        let later = Shell::connect(&hub).await;
        later.wait("its snapshot", |s| s.lock_screen_notifications == Some(false)).await;
    });
}

#[test]
fn do_not_disturb_is_the_same_for_the_shell_and_the_settings() {
    local(async {
        let dir = TempDir::new("settings-dnd");
        let hub = hub_with_settings(&dir);
        let shell = Shell::connect(&hub).await;
        let settings = SettingsClient::connect(&hub).await;
        let until = now_ms() + 3_600_000;
        settings.set_do_not_disturb(true, until).await;
        shell.wait("on for the shell", |s| s.dnd_enabled && s.dnd_until == until).await;
        settings.wait("on for the settings", |s| s.dnd_enabled && s.dnd_until == until).await;
        // From the shell's tile: the settings see it
        shell.set_dnd(false, 0).await;
        settings.wait("off from the shell", |s| !s.dnd_enabled).await;
    });
}

#[test]
fn the_settings_come_back_after_a_restart() {
    local(async {
        let dir = TempDir::new("settings-kept");
        {
            let hub = hub_with_settings(&dir);
            let settings = SettingsClient::connect(&hub).await;
            let sender = Sender::connect(&hub).await;
            sender.send(send_as("org.maia.mail", "Mail", "Hello")).await;
            settings.wait("Mail listed", |s| s.apps.contains_key("org.maia.mail")).await;
            settings.set_app_enabled("org.maia.mail", false).await;
            settings.set_lock_screen_notifications(false).await;
            settings.set_do_not_disturb(true, 0).await;
            tokio::time::sleep(SETTINGS_SAVE_DELAY + Duration::from_millis(200)).await;
        }
        let text = std::fs::read_to_string(dir.0.join(FILE_NAME)).unwrap();
        assert!(text.contains("org.maia.mail"), "{text}");

        // The service again, as after a new login
        let hub = hub_with_settings(&dir);
        let shell = Shell::connect(&hub).await;
        let settings = SettingsClient::connect(&hub).await;
        let seen = settings.seen.borrow();
        assert!(seen.dnd_enabled && !seen.lock_screen_notifications);
        assert!(!seen.apps["org.maia.mail"].enabled);
        drop(seen);
        shell.wait("the shell's snapshot", |s| s.dnd_enabled && s.lock_screen_notifications == Some(false)).await;
        // Do not disturb holds again: a new notification does not pop up
        let sender = Sender::connect(&hub).await;
        let sent = sender.send(send_as("", "notify-send", "Quiet")).await;
        shell.wait("in the list", |s| s.notifications.contains_key(&sent.id)).await;
        assert!(!shell.shown(sent.id).unwrap().popup);
    });
}

#[test]
fn do_not_disturb_whose_time_ran_out_while_away_is_off() {
    local(async {
        let dir = TempDir::new("settings-expired");
        std::fs::write(dir.0.join(FILE_NAME), r#"{ "doNotDisturb": { "enabled": true, "until": 1000 } }"#).unwrap();
        let hub = hub_with_settings(&dir);
        let settings = SettingsClient::connect(&hub).await;
        assert!(!settings.seen.borrow().dnd_enabled);
    });
}

#[test]
fn applications_that_declare_notifications_are_listed_before_they_send() {
    local(async {
        let dir = TempDir::new("settings-declared");
        let applications = dir.0.join("data/applications");
        std::fs::create_dir_all(&applications).unwrap();
        std::fs::write(
            applications.join("org.gnome.Calendar.desktop"),
            "[Desktop Entry]\nName=Calendar\nIcon=org.gnome.Calendar\nX-GNOME-UsesNotifications=true\n",
        )
        .unwrap();
        std::fs::write(applications.join("org.maia.mail.desktop"), "[Desktop Entry]\nName=Maia Mail\nIcon=mail-client\n").unwrap();
        let hub = hub_with_settings(&dir);
        let settings = SettingsClient::connect(&hub).await;
        settings.wait("Calendar declared", |s| s.apps.contains_key("org.gnome.Calendar")).await;
        let calendar = settings.seen.borrow().apps["org.gnome.Calendar"].clone();
        assert!(calendar.declared && !calendar.sent && calendar.enabled);
        assert_eq!(calendar.app_name, "Calendar");

        // A sender with a desktop entry is named by it, not by what it sent
        let sender = Sender::connect(&hub).await;
        sender.send(send_as("org.maia.mail", "mail-daemon", "Hello")).await;
        settings.wait("Mail listed", |s| s.apps.contains_key("org.maia.mail")).await;
        let mail = settings.seen.borrow().apps["org.maia.mail"].clone();
        assert_eq!((mail.app_name.as_str(), mail.app_icon.as_str()), ("Maia Mail", "mail-client"));
    });
}

/// A shell built on the contract before ShellSettings: it answers shellSettingsChanged with
/// "unimplemented", and must still get its notifications
struct OldShell(Rc<std::cell::Cell<u32>>);

impl center_listener::Server for OldShell {
    async fn snapshot(
        self: Rc<Self>,
        _: center_listener::SnapshotParams,
        _: center_listener::SnapshotResults,
    ) -> Result<(), capnp::Error> {
        Ok(())
    }

    async fn changes(
        self: Rc<Self>,
        params: center_listener::ChangesParams,
        _: center_listener::ChangesResults,
    ) -> Result<(), capnp::Error> {
        self.0.set(self.0.get() + params.get()?.get_changed()?.len());
        Ok(())
    }
}

#[test]
fn an_older_shell_keeps_its_notifications() {
    local(async {
        let dir = TempDir::new("settings-old-shell");
        let hub = hub_with_settings(&dir);
        let center: notification_center::Client = maia_notifications::rpc::Center::client(hub.clone());
        let changed = Rc::new(std::cell::Cell::new(0));
        let mut request = center.watch_request();
        request.get().set_listener(capnp_rpc::new_client(OldShell(changed.clone())));
        let _subscription = request.send().promise.await.unwrap().get().unwrap().get_subscription().unwrap();
        let settings = SettingsClient::connect(&hub).await;
        settings.set_lock_screen_notifications(false).await;
        tokio::time::sleep(Duration::from_millis(50)).await;
        let sender = Sender::connect(&hub).await;
        sender.send(send_as("", "notify-send", "Still here")).await;
        common::eventually("the old shell's notification", || changed.get() > 0).await;
    });
}
