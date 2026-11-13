#pragma once

// ServiceLink: a connection to one socket of the notification service, with Cap'n Proto in its own
// thread (a KJ event loop), so that the GUI thread never waits for the service:
//
//   GUI thread                          KJ thread
//   post(task) ──► queue + eventfd ───► task(tasks): requests to the service
//   toGui(f)   ◄── queued call ◄──────── calls of the service (listeners), answers
//
// The link connects at start() and again every second while the service is not there (its start, a
// crash, a restart); connected() and disconnected() tell a subclass, in the KJ thread, to set up and
// drop what belongs to one connection. Tasks posted while there is no connection are dropped: a
// subclass that must not lose them keeps them itself until the next connection.
//
// A subclass calls start() at the end of its constructor and stop() first in its destructor (the
// thread calls its virtual functions).
//
// Shared by Maia.Notifications (the Notifier socket) and Maia.Notifications.Center (the
// NotificationCenter socket).

#include <QObject>
#include <QString>

#include <capnp/capability.h>
#include <kj/async.h>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaNotifications {

class ServiceLink : public QObject
{
    Q_OBJECT

public:
    using Task = std::function<void(kj::TaskSet &)>;

    // logName: the prefix of warnings ("Maia.Notifications")
    ServiceLink(const QString &socketPath, const QString &logName, QObject *parent = nullptr);
    ~ServiceLink() override;

    QString socketPath() const { return m_socketPath; }
    bool isConnected() const { return m_connected; }

    // GUI thread: runs `task` in the KJ thread while connected; dropped without a connection
    void post(Task task);

    // $XDG_RUNTIME_DIR/maia/<name>-<WAYLAND_DISPLAY>.sock, unless `variable` names one
    static QString socketPathFor(const char *variable, const QString &name);

Q_SIGNALS:
    void connectedChanged();

protected:
    void start();
    void stop();

    // KJ thread: a connection is up; keep what it needs (bootstrap.castAs<…>(), a listener)
    virtual void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) = 0;
    // KJ thread: the connection is gone; drop every capability of it
    virtual void disconnected() = 0;

    // KJ thread → GUI thread, in order
    template<typename F>
    void toGui(F f)
    {
        QMetaObject::invokeMethod(this, std::move(f), Qt::QueuedConnection);
    }

    QString logName() const { return m_logName; }

private:
    void run();
    void wake();
    void setConnected(bool connected);

    const QString m_socketPath;
    const QString m_logName;
    bool m_connected = false;
    std::atomic<bool> m_linked{false};

    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
};

} // namespace MaiaNotifications
