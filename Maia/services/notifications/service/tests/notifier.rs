//! The Cap'n Proto doors: Maia senders (Notifier) and shells (NotificationCenter) over real
//! connections, without D-Bus.

mod common;

use std::time::Duration;

use common::{Sender, Shell, TempDir, local};
use maia_notifications::model::now_ms;
use maia_notifications::notifications_capnp as n;

#[test]
fn a_maia_notification_reaches_the_shell() {
    local(async {
        let dir = TempDir::new("maia");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender
            .send(|mut r| {
                r.set_app_name("Power");
                r.set_desktop_entry("org.maia.settings.desktop");
                r.set_app_icon("battery-caution-symbolic");
                r.set_summary("Battery low");
                r.set_body("10 % left. Connect the charger.");
                r.set_image("/tmp/picture of me.png");
                r.set_urgency(n::Urgency::Critical);
                r.set_timeout(-1);
            })
            .await;
        shell.wait("the notification", |s| s.notifications.contains_key(&sent.id)).await;
        let shown = shell.shown(sent.id).unwrap();
        assert_eq!(shown.app_name, "Power");
        assert_eq!(shown.desktop_entry, "org.maia.settings");
        assert_eq!(shown.summary, "Battery low");
        assert_eq!(shown.image, "file:///tmp/picture%20of%20me.png");
        assert_eq!(shown.urgency, n::Urgency::Critical);
        assert!(shown.popup);
    });
}

#[test]
fn only_the_sender_hears_its_action_with_the_token() {
    local(async {
        let dir = TempDir::new("maia-action");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let fill = |mut r: n::notification_request::Builder| {
            r.set_summary("Update ready");
            let mut actions = r.init_actions(1);
            actions.reborrow().get(0).set_key("restart");
            actions.reborrow().get(0).set_label("Restart now");
        };
        let a = sender.send(fill).await;
        let b = sender.send(fill).await;
        shell.wait("both", |s| s.notifications.len() == 2).await;
        assert_eq!(shell.invoke(a.id, "restart", "xdg-token").await, n::ErrorCode::None);
        a.hear("action restart xdg-token").await;
        a.hear("closed Dismissed").await;
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(b.heard.borrow().events.is_empty());
    });
}

#[test]
fn the_handle_updates_and_closes_its_notification() {
    local(async {
        let dir = TempDir::new("maia-handle");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender.send(|mut r| r.set_summary("Copying 1 of 10")).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&sent.id)).await;

        let mut update = sent.handle.update_request();
        update.get().init_notification().set_summary("Copying 9 of 10");
        let result = update.send().promise.await.unwrap();
        assert_eq!(result.get().unwrap().get_result().unwrap().get_error().unwrap(), n::ErrorCode::None);
        shell.wait("the update", |s| s.notifications.get(&sent.id).is_some_and(|n| n.summary == "Copying 9 of 10")).await;
        assert_eq!(shell.seen.borrow().notifications.len(), 1);

        sent.handle.close_request().send().promise.await.unwrap();
        sent.hear("closed ClosedByApp").await;
        shell.wait("the removal", |s| s.notifications.is_empty()).await;

        // An update of a closed notification says so
        let mut update = sent.handle.update_request();
        update.get().init_notification().set_summary("again");
        let result = update.send().promise.await.unwrap();
        assert_eq!(result.get().unwrap().get_result().unwrap().get_error().unwrap(), n::ErrorCode::NotFound);
    });
}

#[test]
fn dropping_the_handle_or_the_sender_leaves_the_notification() {
    local(async {
        let dir = TempDir::new("maia-drop");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender.send(|mut r| r.set_summary("Backup finished")).await;
        let id = sent.id;
        drop(sent);
        drop(sender);
        tokio::time::sleep(Duration::from_millis(50)).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&id)).await;
        // Its actions cannot reach anyone, which is no error for the shell
        assert_eq!(shell.dismiss(id).await, n::ErrorCode::None);
    });
}

#[test]
fn replies_reach_the_sender() {
    local(async {
        let dir = TempDir::new("maia-reply");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender
            .send(|mut r| {
                r.set_summary("Anna");
                r.set_inline_reply(true);
                r.set_reply_placeholder("Reply to Anna…");
            })
            .await;
        shell.wait("the notification", |s| s.notifications.contains_key(&sent.id)).await;
        assert_eq!(shell.reply(sent.id, "On my way", "").await, n::ErrorCode::None);
        sent.hear("replied On my way ").await;
        sent.hear("closed Dismissed").await;
    });
}

#[test]
fn a_reconnecting_shell_gets_the_whole_list_newest_first() {
    local(async {
        let dir = TempDir::new("maia-snapshot");
        let hub = common::hub(&dir);
        let sender = Sender::connect(&hub).await;
        let first = sender.send(|mut r| r.set_summary("first")).await;
        let second = sender.send(|mut r| r.set_summary("second")).await;
        let mut shell = Shell::connect(&hub).await;
        assert_eq!(shell.seen.borrow().snapshot_order, [second.id, first.id]);
        assert_eq!(hub.borrow().listener_count(), 1);
        // A shell that goes away stops getting calls
        shell.unsubscribe();
        common::eventually("the listener removed", || hub.borrow().listener_count() == 0).await;
        let again = Shell::connect(&hub).await;
        assert_eq!(again.seen.borrow().snapshot_order, [second.id, first.id]);
    });
}

#[test]
fn clear_all_keeps_critical_notifications() {
    local(async {
        let dir = TempDir::new("maia-clear");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        sender.send(|mut r| r.set_summary("a")).await;
        sender.send(|mut r| r.set_summary("b")).await;
        let critical = sender
            .send(|mut r| {
                r.set_summary("battery");
                r.set_urgency(n::Urgency::Critical);
            })
            .await;
        shell.wait("three", |s| s.notifications.len() == 3).await;
        shell.dismiss_all().await;
        shell.wait("only the critical one", |s| s.notifications.len() == 1 && s.notifications.contains_key(&critical.id)).await;
    });
}

#[test]
fn do_not_disturb_ends_by_itself_at_its_time() {
    local(async {
        let dir = TempDir::new("maia-dnd");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let until = now_ms() + 300;
        shell.set_dnd(true, until).await;
        shell.wait("on", |s| s.dnd_enabled && s.dnd_active && s.dnd_until == until).await;
        let quiet = sender.send(|mut r| r.set_summary("during")).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&quiet.id)).await;
        assert!(!shell.shown(quiet.id).unwrap().popup);
        shell.wait("off by itself", |s| !s.dnd_enabled && !s.dnd_active && s.dnd_until == 0).await;
        let loud = sender.send(|mut r| r.set_summary("after")).await;
        shell.wait("the notification", |s| s.notifications.contains_key(&loud.id)).await;
        assert!(shell.shown(loud.id).unwrap().popup);
        // A request without an urgency is a normal one
        assert_eq!(shell.shown(loud.id).unwrap().urgency, n::Urgency::Normal);
        // Turned on again, an older timer does nothing
        shell.set_dnd(true, now_ms() + 100).await;
        shell.set_dnd(true, 0).await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(shell.seen.borrow().dnd_enabled, "{:#?}", shell.seen.borrow());
    });
}

#[test]
fn low_urgency_goes_into_the_list_without_a_popup() {
    local(async {
        let dir = TempDir::new("maia-low");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender
            .send(|mut r| {
                r.set_summary("Battery charged");
                r.set_urgency(n::Urgency::Low);
            })
            .await;
        shell.wait("the notification", |s| s.notifications.contains_key(&sent.id)).await;
        assert!(!shell.shown(sent.id).unwrap().popup);
    });
}

#[test]
fn a_maia_program_attaches_files() {
    local(async {
        let dir = TempDir::new("maia-files");
        let hub = common::hub(&dir);
        let shell = Shell::connect(&hub).await;
        let sender = Sender::connect(&hub).await;
        let sent = sender
            .send(|mut r| {
                r.set_summary("Export finished");
                let mut urls = r.init_urls(3);
                urls.set(0, "/home/a/Videos/holiday.mkv");
                urls.set(1, "data:text/html,<b>x</b>");
                urls.set(2, "/home/a/Videos/holiday.mkv");
            })
            .await;
        shell.wait("the notification", |s| s.notifications.contains_key(&sent.id)).await;
        assert_eq!(shell.shown(sent.id).unwrap().urls, ["file:///home/a/Videos/holiday.mkv"]);
    });
}

