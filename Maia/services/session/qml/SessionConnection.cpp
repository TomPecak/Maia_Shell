#include "SessionConnection.h"

#include "session.capnp.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>

#include <QCoreApplication>
#include <QDebug>
#include <QDir>

#include <sys/eventfd.h>
#include <unistd.h>

namespace C = MaiaSession::Contract;

namespace MaiaSession {

// What exists only in the KJ thread, for one connection
struct KjContext {
    C::SessionService::Client service;
    C::SessionControl::Client control;
    kj::TaskSet &tasks;
};

namespace {

QString toQString(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

State toState(C::State state)
{
    switch (state) {
    case C::State::STARTING:
        return State::Starting;
    case C::State::RUNNING:
        return State::Running;
    case C::State::ENDING:
        return State::Ending;
    case C::State::SLEEPING:
        return State::Sleeping;
    }
    return State::Starting;
}

EndAction toEndAction(C::EndAction action)
{
    switch (action) {
    case C::EndAction::LOGOUT:
        return EndAction::Logout;
    case C::EndAction::REBOOT:
        return EndAction::Reboot;
    case C::EndAction::POWER_OFF:
        return EndAction::PowerOff;
    }
    return EndAction::Logout;
}

Ability toAbility(C::Ability ability)
{
    switch (ability) {
    case C::Ability::YES:
        return Ability::Yes;
    case C::Ability::CHALLENGE:
        return Ability::Challenge;
    case C::Ability::NO:
        break;
    }
    return Ability::No;
}

Capabilities toCapabilities(C::Capabilities::Reader c)
{
    Capabilities caps;
    caps.logout = c.getLogout();
    caps.powerOff = toAbility(c.getPowerOff());
    caps.reboot = toAbility(c.getReboot());
    caps.suspend = toAbility(c.getSuspend());
    caps.hibernate = toAbility(c.getHibernate());
    caps.hybridSleep = toAbility(c.getHybridSleep());
    caps.suspendThenHibernate = toAbility(c.getSuspendThenHibernate());
    return caps;
}

QString kindName(C::ChildKind kind)
{
    switch (kind) {
    case C::ChildKind::COMPOSITOR:
        return QStringLiteral("compositor");
    case C::ChildKind::SHELL:
        return QStringLiteral("shell");
    case C::ChildKind::MAIA_SERVICE:
        return QStringLiteral("maiaService");
    case C::ChildKind::KDE_SERVICE:
        return QStringLiteral("kdeService");
    case C::ChildKind::HELPER:
        return QStringLiteral("helper");
    }
    return QString();
}

QString childStateName(C::ChildState state)
{
    switch (state) {
    case C::ChildState::WAITING:
        return QStringLiteral("waiting");
    case C::ChildState::RUNNING:
        return QStringLiteral("running");
    case C::ChildState::RESTARTING:
        return QStringLiteral("restarting");
    case C::ChildState::FAILED:
        return QStringLiteral("failed");
    case C::ChildState::STOPPED:
        return QStringLiteral("stopped");
    }
    return QString();
}

ChildInfo toChild(C::Child::Reader c)
{
    ChildInfo child;
    child.name = toQString(c.getName());
    child.kind = kindName(c.getKind());
    child.state = childStateName(c.getState());
    child.pid = c.getPid();
    child.restarts = c.getRestarts();
    child.lastExit = toQString(c.getLastExit());
    return child;
}

Error toError(C::ErrorCode error)
{
    switch (error) {
    case C::ErrorCode::NONE:
        return Error::None;
    case C::ErrorCode::NOT_ALLOWED:
        return Error::NotAllowed;
    case C::ErrorCode::NOT_SUPPORTED:
        return Error::NotSupported;
    case C::ErrorCode::BUSY:
        return Error::Busy;
    case C::ErrorCode::NOT_FOUND:
        return Error::NotFound;
    case C::ErrorCode::FAILED:
        break;
    }
    return Error::Failed;
}

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    void taskFailed(kj::Exception &&exception) override
    {
        qWarning() << "[Maia.Session]" << exception.getDescription().cStr();
    }
};

SessionConnection *s_instance = nullptr;

} // namespace

// Called by the service (in the KJ thread); hands the changes to the GUI thread in their order
class Listener final : public C::SessionListener::Server
{
public:
    explicit Listener(SessionConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        auto params = context.getParams();
        const State state = toState(params.getState());
        const EndAction action = toEndAction(params.getEnding().getAction());
        const bool byUser = params.getEnding().getInitiator() == C::Initiator::USER;
        const Capabilities caps = toCapabilities(params.getCapabilities());
        QList<ChildInfo> children;
        for (auto child : params.getChildren())
            children.append(toChild(child));
        m_connection->toGui([c = m_connection, state, action, byUser, caps, children] {
            c->applySnapshot(state, action, byUser, caps, children);
        });
        return kj::READY_NOW;
    }

    kj::Promise<void> stateChanged(StateChangedContext context) override
    {
        auto params = context.getParams();
        const State state = toState(params.getState());
        const EndAction action = toEndAction(params.getEnding().getAction());
        const bool byUser = params.getEnding().getInitiator() == C::Initiator::USER;
        m_connection->toGui([c = m_connection, state, action, byUser] { c->applyState(state, action, byUser); });
        return kj::READY_NOW;
    }

    kj::Promise<void> capabilitiesChanged(CapabilitiesChangedContext context) override
    {
        const Capabilities caps = toCapabilities(context.getParams().getCapabilities());
        m_connection->toGui([c = m_connection, caps] { c->applyCapabilities(caps); });
        return kj::READY_NOW;
    }

    kj::Promise<void> childChanged(ChildChangedContext context) override
    {
        const ChildInfo child = toChild(context.getParams().getChild());
        m_connection->toGui([c = m_connection, child] { c->applyChild(child); });
        return kj::READY_NOW;
    }

private:
    SessionConnection *m_connection;
};

SessionConnection::SessionConnection(const QString &socketPath, QObject *parent)
    : QObject(parent)
    , m_socketPath(socketPath)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    m_thread = std::thread([this] { run(); });
}

SessionConnection::~SessionConnection()
{
    m_quit = true;
    wake();
    m_thread.join();
    ::close(m_eventFd);
    if (s_instance == this)
        s_instance = nullptr;
}

SessionConnection *SessionConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new SessionConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString SessionConnection::defaultSocketPath()
{
    const QString explicitPath = qEnvironmentVariable("MAIA_SESSION_SOCKET");
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    return runtime + QStringLiteral("/maia/session-") + qEnvironmentVariable("XDG_SESSION_ID") + QStringLiteral(".sock");
}

// --- GUI thread ---

void SessionConnection::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    Q_EMIT connectedChanged();
}

void SessionConnection::applyState(State state, EndAction action, bool byUser)
{
    if (m_state == state && m_endingAction == action && m_endingByUser == byUser)
        return;
    m_state = state;
    m_endingAction = action;
    m_endingByUser = byUser;
    Q_EMIT stateChanged();
}

void SessionConnection::applyCapabilities(const Capabilities &capabilities)
{
    if (m_capabilities == capabilities)
        return;
    m_capabilities = capabilities;
    Q_EMIT capabilitiesChanged();
}

void SessionConnection::applySnapshot(State state, EndAction action, bool byUser, const Capabilities &capabilities,
                                      const QList<ChildInfo> &children)
{
    applyState(state, action, byUser);
    applyCapabilities(capabilities);
    m_children = children;
    Q_EMIT childrenReset();
    setConnected(true);
}

void SessionConnection::applyChild(const ChildInfo &child)
{
    for (int row = 0; row < m_children.size(); ++row) {
        if (m_children[row].name == child.name) {
            if (m_children[row] == child)
                return;
            m_children[row] = child;
            Q_EMIT childChanged(row);
            return;
        }
    }
    m_children.append(child);
    Q_EMIT childAdded(int(m_children.size()) - 1);
}

// --- KJ thread ---

void SessionConnection::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void SessionConnection::post(Task task)
{
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

void SessionConnection::run()
{
    kj::AsyncIoContext io = kj::setupAsyncIo();
    kj::UnixEventPort::FdObserver wakeObserver(io.unixEventPort, m_eventFd, kj::UnixEventPort::FdObserver::OBSERVE_READ);
    auto drainWake = [this] {
        uint64_t value;
        [[maybe_unused]] auto read = ::read(m_eventFd, &value, sizeof(value));
    };
    LogErrors errors;
    bool reportedFailure = false;

    while (!m_quit) {
        bool wasConnected = false;
        try {
            auto address = io.provider->getNetwork()
                               .parseAddress(kj::str("unix:", m_socketPath.toUtf8().constData()))
                               .wait(io.waitScope);
            auto stream = address->connect().wait(io.waitScope);
            capnp::TwoPartyClient client(*stream);
            kj::TaskSet tasks(errors);

            auto service = client.bootstrap().castAs<C::SessionService>();
            // Pipelining: the control capability is usable at once, without waiting for the answer
            KjContext context{service, service.controlRequest().send().getControl(), tasks};

            auto watch = service.watchRequest();
            watch.setListener(kj::heap<Listener>(this));
            auto watched = watch.send();
            // Kept for the whole connection: releasing it would stop the listener
            auto subscription = watched.getSubscription();
            tasks.add(watched.ignoreResult());

            bool disconnected = false;
            auto disconnect = client.onDisconnect()
                                  .then([&] { disconnected = true; }, [&](kj::Exception &&) { disconnected = true; })
                                  .fork();

            wasConnected = true;
            reportedFailure = false;
            qInfo() << "[Maia.Session] connected to" << m_socketPath;

            while (!m_quit && !disconnected) {
                std::deque<Task> queue;
                {
                    std::lock_guard lock(m_mutex);
                    queue.swap(m_queue);
                }
                for (auto &task : queue) {
                    try {
                        task(context);
                    } catch (const kj::Exception &exception) {
                        qWarning() << "[Maia.Session]" << exception.getDescription().cStr();
                    }
                }
                wakeObserver.whenBecomesReadable().exclusiveJoin(disconnect.addBranch()).wait(io.waitScope);
                drainWake();
            }
        } catch (const kj::Exception &exception) {
            if (!reportedFailure)
                qWarning() << "[Maia.Session] no session service at" << m_socketPath << ":"
                           << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo() << "[Maia.Session] disconnected, retrying";
        }
        // Requests made while there is no service fail at once (the user sees nothing happen otherwise)
        std::deque<Task> dropped;
        {
            std::lock_guard lock(m_mutex);
            dropped.swap(m_queue);
        }
        if (!dropped.empty()) {
            qWarning() << "[Maia.Session]" << dropped.size() << "request(s) dropped: no session service";
        }
        if (m_quit)
            break;
        io.provider->getTimer().afterDelay(1 * kj::SECONDS).exclusiveJoin(wakeObserver.whenBecomesReadable()).wait(io.waitScope);
        drainWake();
    }
}

// --- Requests (GUI thread) ---

void SessionConnection::request(Action action)
{
    if (!m_connected) {
        Q_EMIT actionFinished(action, Error::Busy, QStringLiteral("no session service"));
        return;
    }
    post([this, action](KjContext &c) {
        auto finish = [this, action](auto &&response) {
            auto result = response.getResult();
            const Error error = toError(result.getError());
            const QString message = toQString(result.getMessage());
            toGui([this, action, error, message] { Q_EMIT actionFinished(action, error, message); });
        };
        auto failed = [this, action](kj::Exception &&exception) {
            const QString message = QString::fromUtf8(exception.getDescription().cStr());
            toGui([this, action, message] { Q_EMIT actionFinished(action, Error::Failed, message); });
        };
        // Copies: then() keeps what it is given, and a named lambda would be kept by reference
        auto add = [&](auto promise) { c.tasks.add(promise.then(kj::cp(finish), kj::cp(failed))); };
        switch (action) {
        case Action::Logout:
            add(c.control.logoutRequest().send());
            break;
        case Action::Reboot:
            add(c.control.rebootRequest().send());
            break;
        case Action::PowerOff:
            add(c.control.powerOffRequest().send());
            break;
        case Action::Suspend:
            add(c.control.suspendRequest().send());
            break;
        case Action::Hibernate:
            add(c.control.hibernateRequest().send());
            break;
        case Action::HybridSleep:
            add(c.control.hybridSleepRequest().send());
            break;
        case Action::SuspendThenHibernate:
            add(c.control.suspendThenHibernateRequest().send());
            break;
        }
    });
}

void SessionConnection::restartChild(const QString &name)
{
    if (!m_connected) {
        Q_EMIT restartChildFinished(name, Error::Busy, QStringLiteral("no session service"));
        return;
    }
    post([this, name](KjContext &c) {
        auto request = c.control.restartChildRequest();
        request.setName(name.toUtf8().constData());
        c.tasks.add(request.send().then(
            [this, name](auto &&response) {
                auto result = response.getResult();
                const Error error = toError(result.getError());
                const QString message = toQString(result.getMessage());
                toGui([this, name, error, message] { Q_EMIT restartChildFinished(name, error, message); });
            },
            [this, name](kj::Exception &&exception) {
                const QString message = QString::fromUtf8(exception.getDescription().cStr());
                toGui([this, name, message] { Q_EMIT restartChildFinished(name, Error::Failed, message); });
            }));
    });
}

} // namespace MaiaSession
