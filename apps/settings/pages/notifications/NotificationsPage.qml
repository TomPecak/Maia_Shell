import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Notifications.Settings

// Settings › Notifications, laid out like GNOME's Notifications panel (Ubuntu 24.04 / 26.04): do
// not disturb and the lock screen first, then each application on or off. GNOME's per-app page
// (sounds, banners, content) is left out for now: one switch per application, in its row.
//
// A whole card toggles its switch (as GNOME's switch rows do): a large target, the switch shows
// the state. The service keeps the settings across sessions and applies them; the lock screen is
// the shells' to show (they read the same setting).
SettingsPage {
    id: page

    title: qsTr("Notifications")

    AppNotificationsModel { id: apps }

    EmptyState {
        visible: !NotificationSettings.connected
        iconName: "notifications-disabled-symbolic"
        title: qsTr("Notification settings unavailable")
        description: qsTr("The notification service (maia-notifications-service) is not running.")
    }

    // "On until 15:30", "On until tomorrow 08:00"
    function untilText(until) {
        const now = new Date()
        const sameDay = until.toDateString() === now.toDateString()
        const time = until.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        return sameDay ? qsTr("On until %1").arg(time)
                       : qsTr("On until %1 %2").arg(until.toLocaleDateString(Qt.locale(), Locale.ShortFormat)).arg(time)
    }

    SettingsGroup {
        visible: NotificationSettings.connected

        SettingsCard {
            id: dndCard

            iconName: "notifications-disabled-symbolic"
            title: qsTr("Do Not Disturb")
            description: NotificationSettings.doNotDisturb && !isNaN(NotificationSettings.doNotDisturbUntil.getTime())
                         ? page.untilText(NotificationSettings.doNotDisturbUntil)
                         : qsTr("Hide popups and mute sounds. Notifications still go to the list.")
            clickable: true
            chevron: false
            onClicked: NotificationSettings.doNotDisturb = !NotificationSettings.doNotDisturb

            LSwitch {
                checked: NotificationSettings.doNotDisturb
                Accessible.name: dndCard.title
                onToggled: NotificationSettings.doNotDisturb = checked
            }
        }

        SettingsCard {
            id: lockCard

            iconName: "lock-symbolic"
            title: qsTr("Lock Screen Notifications")
            description: qsTr("Show notifications while the screen is locked")
            clickable: true
            chevron: false
            onClicked: NotificationSettings.lockScreenNotifications = !NotificationSettings.lockScreenNotifications

            LSwitch {
                checked: NotificationSettings.lockScreenNotifications
                Accessible.name: lockCard.title
                onToggled: NotificationSettings.lockScreenNotifications = checked
            }
        }
    }

    SettingsGroup {
        visible: NotificationSettings.connected
        title: qsTr("App Notifications")

        SettingsCard {
            visible: apps.count === 0
            iconName: "notification-inactive-symbolic"
            title: qsTr("No apps yet")
            description: qsTr("An app appears here once it sends a notification.")
        }

        Repeater {
            model: apps

            SettingsCard {
                id: appCard

                // model.*: the roles "enabled" and "appIcon" would shadow the card's own properties
                readonly property bool allowed: model.enabled

                appIcon: true
                iconName: model.appIcon.length > 0 ? model.appIcon : "application-x-executable"
                title: model.appName
                description: appCard.allowed ? "" : qsTr("Its notifications are not shown")
                clickable: true
                chevron: false
                onClicked: NotificationSettings.setAppEnabled(model.key, !appCard.allowed)

                LSwitch {
                    checked: appCard.allowed
                    Accessible.name: appCard.title
                    onToggled: NotificationSettings.setAppEnabled(model.key, checked)
                }
            }
        }
    }
}
