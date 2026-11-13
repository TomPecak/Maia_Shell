#pragma once

// The connection of a shell to the NotificationCenter of the notification service. One per
// process (instance()), shared by NotificationCenter, NotificationsModel and NotificationPopupsModel.
//
// The service sends the whole list first, then batches of changes (at most one per frame); a batch
// is read into Qt values in the KJ thread and applied in the GUI thread as a whole: the models
// update once per batch. The last list stays while the service is away (connected is false).
//
// Socket: $MAIA_NOTIFICATIONS_CENTER_SOCKET, or
//         $XDG_RUNTIME_DIR/maia/notifications-center-$WAYLAND_DISPLAY.sock

#include "Contract.h"
#include "ServiceLink.h"

#include <QHash>
#include <QList>

#include <optional>

namespace MaiaNotifications {

class CenterConnection final : public ServiceLink
{
    Q_OBJECT

public:
    explicit CenterConnection(const QString &socketPath, QObject *parent = nullptr);
    ~CenterConnection() override;

    static CenterConnection *instance();
    static QString defaultSocketPath();

    // The current list by id (the snapshot and every batch since); the models keep their order
    const QHash<quint32, NotificationData> &notifications() const { return m_notifications; }
    const DoNotDisturbData &doNotDisturb() const { return m_doNotDisturb; }
    // A notification by id, or nullptr
    const NotificationData *find(quint32 id) const;

    // Requests; failures only go to the log (the notification was gone, the service away)
    void invokeAction(quint32 id, const QString &key, const QString &activationToken);
    void reply(quint32 id, const QString &text, const QString &activationToken);
    void dismiss(quint32 id);
    void expire(quint32 id);
    void dismissAll();
    // until: ms since 1970, 0 = until turned off
    void setDoNotDisturb(bool enabled, qint64 until);

Q_SIGNALS:
    // The whole list again (a new connection)
    void reset();
    // One batch: new or changed notifications, and removed ids
    void batch(const QList<MaiaNotifications::NotificationData> &changed, const QList<quint32> &removed);
    void doNotDisturbChanged();

protected:
    void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) override;
    void disconnected() override;

private:
    friend class ShellListener;

    // GUI thread
    void applySnapshot(const QList<NotificationData> &list, const DoNotDisturbData &dnd);
    void applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed);
    void applyDoNotDisturb(const DoNotDisturbData &dnd);

    QHash<quint32, NotificationData> m_notifications;
    DoNotDisturbData m_doNotDisturb;

    // KJ thread
    std::optional<C::NotificationCenter::Client> m_center;
    std::optional<C::Subscription::Client> m_subscription;
};

} // namespace MaiaNotifications
