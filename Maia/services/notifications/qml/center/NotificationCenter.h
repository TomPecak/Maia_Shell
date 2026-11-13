#pragma once

// NotificationCenter: the notification service for a shell, a singleton.
//
//   import Maia.Notifications.Center
//
//   Badge { count: NotificationCenter.count }
//   ToggleTile { checked: NotificationCenter.doNotDisturb; onToggled: NotificationCenter.doNotDisturb = checked }
//   Button { onClicked: NotificationCenter.invokeAction(model.notificationId, "default", Window.window) }
//
// The lists are NotificationsModel (all) and NotificationPopupsModel (the popups now). Actions and
// replies take the window that was clicked: the shell asks the compositor for an activation token
// for it, so that the application may raise its window; the request goes out when the token is
// there (at most kTokenWait later, then without one).

#include <QDateTime>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <functional>

#include <QWindow>

namespace MaiaNotifications {

class NotificationCenter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // How many notifications the list has
    Q_PROPERTY(int count READ count NOTIFY countChanged)

    // The user's choice; while on, notifications go into the list without a popup (critical ones
    // still pop up)
    Q_PROPERTY(bool doNotDisturb READ doNotDisturb WRITE setDoNotDisturb NOTIFY doNotDisturbChanged)
    // When the user's choice ends by itself; invalid = until turned off
    Q_PROPERTY(QDateTime doNotDisturbUntil READ doNotDisturbUntil NOTIFY doNotDisturbChanged)
    // Quiet now: the user's choice or an application (a presentation)
    Q_PROPERTY(bool doNotDisturbActive READ doNotDisturbActive NOTIFY doNotDisturbChanged)
    // Applications that asked for quiet: [{ desktopEntry, appName, reason }]
    Q_PROPERTY(QVariantList inhibitors READ inhibitors NOTIFY doNotDisturbChanged)

public:
    // The numbers are those of the contract (notifications.capnp)
    enum Urgency { Normal, Low, Critical };
    Q_ENUM(Urgency)
    enum JobState { JobRunning, JobSuspended, JobFinished, JobFailed };
    Q_ENUM(JobState)

    explicit NotificationCenter(QObject *parent = nullptr);

    static constexpr int kTokenWait = 300;

    bool connected() const;
    int count() const;
    bool doNotDisturb() const;
    void setDoNotDisturb(bool enabled);
    QDateTime doNotDisturbUntil() const;
    bool doNotDisturbActive() const;
    QVariantList inhibitors() const;

    // key "default": a click on the notification itself
    Q_INVOKABLE void invokeAction(uint notificationId, const QString &key, QWindow *window = nullptr);
    Q_INVOKABLE void reply(uint notificationId, const QString &text, QWindow *window = nullptr);
    Q_INVOKABLE void dismiss(uint notificationId);
    // "Clear all": every notification but critical ones
    Q_INVOKABLE void dismissAll();
    // Do not disturb for `minutes`, then off by itself
    Q_INVOKABLE void setDoNotDisturbFor(int minutes);

    // Jobs (JobsModel): the application is asked to cancel or pause; a finished or failed job
    // leaves the list
    Q_INVOKABLE void cancelJob(uint jobId);
    Q_INVOKABLE void suspendJob(uint jobId, bool suspended);
    Q_INVOKABLE void dismissJob(uint jobId);

Q_SIGNALS:
    void connectedChanged();
    void countChanged();
    void doNotDisturbChanged();

private:
    // Calls `send` with an activation token for `window` (or "" without one)
    void withToken(QWindow *window, const QString &appId, std::function<void(const QString &)> send);
};

} // namespace MaiaNotifications
