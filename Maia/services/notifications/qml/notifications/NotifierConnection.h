#pragma once

// The connection of a process to the Notifier of the notification service (the senders' socket).
// One per process (instance()), shared by every Notification object.
//
// Notifications sent while the service is not there (the session is starting, the service
// restarts) wait and go out when it comes; at most kMaxWaiting, the oldest are dropped. When the
// connection ends, the service has lost its list (it keeps nothing on disk): every shown
// notification counts as closed (reason Other).
//
// Socket: $MAIA_NOTIFICATIONS_SOCKET, or $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock

#include "Contract.h"
#include "ServiceLink.h"

#include <QHash>
#include <QList>
#include <QSet>

#include <map>
#include <mutex>
#include <vector>
#include <optional>

namespace MaiaNotifications {

class Notification;

class NotifierConnection final : public ServiceLink
{
    Q_OBJECT

public:
    explicit NotifierConnection(const QString &socketPath, QObject *parent = nullptr);
    ~NotifierConnection() override;

    static NotifierConnection *instance();
    static QString defaultSocketPath();

    static constexpr int kMaxWaiting = 32;

    // A new notification of `object`; returns this process's number for it. What happens to it is
    // told to `object` alone (a direct call, not a signal every object would have to filter)
    int send(const RequestData &request, Notification *object);
    // Replaces the content of a sent notification
    void update(int local, const RequestData &request);
    void close(int local);
    // Its object is gone: the handle is dropped, the notification stays
    void release(int local);

protected:
    void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) override;
    void disconnected() override;

private:
    friend class SenderListener;

    void postSend(int local, const RequestData &request);
    void flushWaiting();
    // GUI thread: to the object of `local`, if it still exists and the notification is shown
    void deliverSent(int local, quint32 id);
    void deliverAction(int local, const QString &key, const QString &token);
    void deliverReply(int local, const QString &text, const QString &token);
    void deliverClosed(int local, int reason);

    // What the service tells, collected in the KJ thread and handed to the GUI thread together:
    // a flood of answers is one queued call, not one per notification
    struct Event {
        enum Kind { Sent, Action, Reply, Closed } kind;
        int local;
        quint32 id = 0;
        QString text;
        QString token;
        int reason = 0;
    };
    void tell(Event event);
    void deliver();

    // GUI thread
    int m_nextLocal = 0;
    QList<QPair<int, RequestData>> m_waiting;
    QSet<int> m_active;
    QHash<int, Notification *> m_objects;

    std::mutex m_eventsMutex;
    std::vector<Event> m_events;

    // KJ thread
    std::optional<C::Notifier::Client> m_notifier;
    std::map<int, C::NotificationHandle::Client> m_handles;
};

} // namespace MaiaNotifications
