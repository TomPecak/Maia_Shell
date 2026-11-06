#pragma once

// The connection of a process to the appearance service (maia-appearance-service), over Cap'n Proto.
//
// One per process (AppearanceSource::instance()), shared by every QML object. Cap'n Proto runs in
// its own thread (KJ event loop), so the GUI thread never waits for the service:
//
//   GUI thread                           KJ thread
//   command ──► queue + eventfd ───────► request to the service
//   callback(result) ◄──── queued ────── its answer
//   AppearanceSource::apply* ◄─ queued ─ DecorationsListener call from the service
//
// The connection is retried every second while the service is not there (its start, a crash);
// meanwhile the state is empty and commands answer Unavailable. Frontend activations
// (FrontendLook) are renewed on every new connection while they are wanted.
//
// Socket: $MAIA_APPEARANCE_SOCKET, or $XDG_RUNTIME_DIR/maia/appearance-$WAYLAND_DISPLAY.sock (the
// same rule as the service).

#include "AppearanceSource.h"

#include <QHash>
#include <QPair>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaAppearance {

struct KjContext;

class AppearanceConnection final : public AppearanceSource
{
    Q_OBJECT

public:
    explicit AppearanceConnection(const QString &socketPath, QObject *parent = nullptr);
    ~AppearanceConnection() override;

    static QString defaultSocketPath();

    void setTheme(const QString &id, Callback done = {}) override;
    void setBorderSize(Appearance::BorderSize size, Callback done = {}) override;
    void install(const QString &path, IdCallback done = {}) override;
    void remove(const QString &id, Callback done = {}) override;
    void refresh() override;
    void activateFrontend(int handle, const QString &frontend, const QString &defaultThemeId) override;
    void deactivateFrontend(int handle) override;

private:
    using Task = std::function<void(KjContext &)>;

    friend class Listener;

    void run();
    // Runs the task in the KJ thread; without a connection the callback gets Unavailable at once
    void post(Task task, const Callback &done = {});
    void wake();
    template<typename F>
    void toGui(F f)
    {
        QMetaObject::invokeMethod(this, std::move(f), Qt::QueuedConnection);
    }

    const QString m_socketPath;
    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    std::atomic<bool> m_live{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
    // Wanted frontend activations (handle -> frontend, default), read by the KJ thread on connect
    QHash<int, QPair<QString, QString>> m_frontends;
};

} // namespace MaiaAppearance
