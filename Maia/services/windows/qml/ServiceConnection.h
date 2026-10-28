#pragma once

// The connection of a process to the window service (maia-windows), over Cap'n Proto.
//
// One per process (instance()), shared by every model. Cap'n Proto runs in its own thread (KJ
// event loop), so the GUI thread never waits for the service:
//
//   GUI thread                          KJ thread
//   command ──► queue + eventfd ──────► request to the service
//   WindowSource::upsert ◄── queued ─── WindowListener call from the service
//
// The connection is retried every second while the service is not there (e.g. during its start or
// after a crash); the list of windows stays meanwhile.
//
// Socket: $MAIA_WINDOWS_SOCKET, or $XDG_RUNTIME_DIR/maia/windows-$WAYLAND_DISPLAY.sock (the same
// rule as the service).

#include "WindowSource.h"

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaWindows {

struct KjContext;

class ServiceConnection final : public WindowSource
{
    Q_OBJECT

public:
    explicit ServiceConnection(const QString &socketPath, QObject *parent = nullptr);
    ~ServiceConnection() override;

    // The connection of this process, created on first use
    static ServiceConnection *instance();
    static QString defaultSocketPath();

    QString socketPath() const { return m_socketPath; }

    void activate(const QString &id) override;
    void close(const QString &id) override;
    void setState(const QString &id, State flag, bool on) override;
    void requestMove(const QString &id) override;
    void requestResize(const QString &id) override;
    void launchNewInstance(const QString &id) override;
    void launch(const QString &launcherUrl) override;

protected:
    void fetchIcon(const QString &id, quint32 serial) override;

private:
    using Task = std::function<void(KjContext &)>;

    friend class Listener;

    void run();
    void post(Task task);
    void wake();
    // Runs f in the GUI thread (dropped when this object is gone)
    template<typename F>
    void toGui(F f)
    {
        QMetaObject::invokeMethod(this, std::move(f), Qt::QueuedConnection);
    }

    const QString m_socketPath;
    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
};

} // namespace MaiaWindows
