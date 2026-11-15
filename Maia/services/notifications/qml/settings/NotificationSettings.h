#pragma once

// NotificationSettings: the user's rules of notifications, for Maia Settings, a singleton.
//
//   import Maia.Notifications.Settings
//
//   LSwitch { checked: NotificationSettings.doNotDisturb; onToggled: NotificationSettings.doNotDisturb = checked }
//   LSwitch { checked: NotificationSettings.lockScreenNotifications
//             onToggled: NotificationSettings.lockScreenNotifications = checked }
//   Repeater { model: AppNotificationsModel {}
//              LSwitch { checked: model.enabled; onToggled: NotificationSettings.setAppEnabled(model.key, checked) } }
//
// The service keeps them across sessions and applies them: do not disturb (no popups and no sounds,
// the notifications go into the list; critical ones still pop up), an application turned off (its
// notifications are dropped). Notifications on the lock screen is the shells' to do: the service
// keeps the choice, every shell reads it (Maia.Notifications.Center). Only rules, no content: this
// module never sees a notification.

#include <QDateTime>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class NotificationSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // The user's do not disturb (the same as the shell's quick settings tile)
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY settingsChanged)
    // When it ends by itself; invalid = until turned off
    Q_PROPERTY(QDateTime doNotDisturbUntil READ doNotDisturbUntil NOTIFY settingsChanged)
    // Applications that asked for quiet now (a presentation): [{ desktopEntry, appName, reason }]
    Q_PROPERTY(QVariantList inhibitors READ inhibitors NOTIFY settingsChanged)
    // Notifications on the lock screen (or only that there are some)
    Q_PROPERTY(bool lockScreenNotifications READ lockScreenNotifications WRITE setLockScreenNotifications NOTIFY settingsChanged)

public:
    explicit NotificationSettings(QObject *parent = nullptr);

    bool connected() const;
    bool doNotDisturb() const;
    void setDoNotDisturb(bool enabled);
    QDateTime doNotDisturbUntil() const;
    QVariantList inhibitors() const;
    bool lockScreenNotifications() const;
    void setLockScreenNotifications(bool enabled);

    // Do not disturb for `minutes`, then off by itself
    Q_INVOKABLE void setDoNotDisturbFor(int minutes);
    // An application of AppNotificationsModel (its key) on or off, for notifications from now on
    Q_INVOKABLE void setAppEnabled(const QString &key, bool enabled);

Q_SIGNALS:
    void connectedChanged();
    void settingsChanged();
};

} // namespace MaiaNotifications
