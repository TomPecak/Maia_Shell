#pragma once

// The connection of a process to the session service (maia-session-service), over Cap'n Proto.
//
// One per process (instance()), shared by Session and SessionChildrenModel. Cap'n Proto runs in
// its own thread (KJ event loop), so the GUI thread never waits for the service:
//
//   GUI thread                          KJ thread
//   logout() ──► queue + eventfd ─────► request to the service
//   state, children ◄── queued ──────── SessionListener call from the service
//
// The connection is retried every second while the service is not there; the last known state
// stays meanwhile (connected is false).
//
// Socket: $MAIA_SESSION_SOCKET (every process of a session has it), or
// $XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock (the same rule as the service).

#include <QList>
#include <QObject>
#include <QString>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaSession {

struct KjContext;

// The values of the contract, plain
enum class State { Starting, Running, Ending, Sleeping };
enum class EndAction { Logout, Reboot, PowerOff };
enum class Ability { No, Yes, Challenge };
enum class Action { Logout, Reboot, PowerOff, Suspend, Hibernate, HybridSleep, SuspendThenHibernate };
enum class Error { None, NotAllowed, NotSupported, Busy, NotFound, Failed };

struct Capabilities {
    bool logout = false;
    Ability powerOff = Ability::No;
    Ability reboot = Ability::No;
    Ability suspend = Ability::No;
    Ability hibernate = Ability::No;
    Ability hybridSleep = Ability::No;
    Ability suspendThenHibernate = Ability::No;

    bool operator==(const Capabilities &) const = default;
};

struct ChildInfo {
    QString name;
    QString kind;  // "compositor", "shell", "maiaService", "kdeService", "helper"
    QString state; // "waiting", "running", "restarting", "failed", "stopped"
    quint32 pid = 0;
    quint32 restarts = 0;
    QString lastExit;

    bool operator==(const ChildInfo &) const = default;
};

class SessionConnection final : public QObject
{
    Q_OBJECT

public:
    explicit SessionConnection(const QString &socketPath, QObject *parent = nullptr);
    ~SessionConnection() override;

    // The connection of this process, created on first use
    static SessionConnection *instance();
    static QString defaultSocketPath();

    QString socketPath() const { return m_socketPath; }

    bool isConnected() const { return m_connected; }
    State state() const { return m_state; }
    EndAction endingAction() const { return m_endingAction; }
    bool endingByUser() const { return m_endingByUser; }
    Capabilities capabilities() const { return m_capabilities; }
    QList<ChildInfo> children() const { return m_children; }

    // The result arrives through actionFinished
    void request(Action action);
    void restartChild(const QString &name);

Q_SIGNALS:
    void connectedChanged();
    void stateChanged();
    void capabilitiesChanged();
    // The whole list (a new connection) or one child
    void childrenReset();
    void childChanged(int row);
    void childAdded(int row);
    void actionFinished(MaiaSession::Action action, MaiaSession::Error error, const QString &message);
    void restartChildFinished(const QString &name, MaiaSession::Error error, const QString &message);

private:
    using Task = std::function<void(KjContext &)>;

    friend class Listener;

    // GUI thread
    void setConnected(bool connected);
    void applyState(State state, EndAction action, bool byUser);
    void applyCapabilities(const Capabilities &capabilities);
    void applySnapshot(State state, EndAction action, bool byUser, const Capabilities &capabilities,
                       const QList<ChildInfo> &children);
    void applyChild(const ChildInfo &child);

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
    bool m_connected = false;
    State m_state = State::Starting;
    EndAction m_endingAction = EndAction::Logout;
    bool m_endingByUser = false;
    Capabilities m_capabilities;
    QList<ChildInfo> m_children;

    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
};

} // namespace MaiaSession
