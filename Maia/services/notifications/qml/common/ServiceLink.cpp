#include "ServiceLink.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>
#include <kj/common.h>

#include <QDebug>
#include <QDir>
#include <QFileInfo>

#include <sys/eventfd.h>
#include <unistd.h>

namespace MaiaNotifications {

namespace {

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    explicit LogErrors(QString name)
        : m_name(std::move(name))
    {
    }

    void taskFailed(kj::Exception &&exception) override
    {
        // A call that fails because the service went away is no news: the link reconnects
        if (exception.getType() != kj::Exception::Type::DISCONNECTED)
            qWarning().noquote() << QString(QLatin1Char('[') + m_name + QLatin1Char(']')) << exception.getDescription().cStr();
    }

private:
    QString m_name;
};

} // namespace

ServiceLink::ServiceLink(const QString &socketPath, const QString &logName, QObject *parent)
    : QObject(parent)
    , m_socketPath(socketPath)
    , m_logName(logName)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
}

ServiceLink::~ServiceLink()
{
    stop();
    ::close(m_eventFd);
}

QString ServiceLink::socketPathFor(const char *variable, const QString &name)
{
    const QString explicitPath = qEnvironmentVariable(variable);
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours (the service's rule)
    const QString display = QFileInfo(qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"))).fileName();
    return runtime + QStringLiteral("/maia/") + name + QLatin1Char('-') + display + QStringLiteral(".sock");
}

void ServiceLink::start()
{
    if (!m_thread.joinable())
        m_thread = std::thread([this] { run(); });
}

void ServiceLink::stop()
{
    if (!m_thread.joinable())
        return;
    m_quit = true;
    wake();
    m_thread.join();
}

void ServiceLink::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    Q_EMIT connectedChanged();
}

void ServiceLink::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void ServiceLink::post(Task task)
{
    if (!m_linked)
        return;
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

void ServiceLink::run()
{
    kj::AsyncIoContext io = kj::setupAsyncIo();
    kj::UnixEventPort::FdObserver wakeObserver(io.unixEventPort, m_eventFd, kj::UnixEventPort::FdObserver::OBSERVE_READ);
    auto drainWake = [this] {
        uint64_t value;
        [[maybe_unused]] auto read = ::read(m_eventFd, &value, sizeof(value));
    };
    LogErrors errors(m_logName);
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
            // Whatever ends this connection, the subclass drops its capabilities first, while the
            // connection still exists
            KJ_DEFER({
                m_linked = false;
                disconnected();
            });

            connected(client.bootstrap(), tasks);
            m_linked = true;
            toGui([this] { setConnected(true); });

            bool disconnectedNow = false;
            auto disconnect = client.onDisconnect()
                                  .then([&] { disconnectedNow = true; }, [&](kj::Exception &&) { disconnectedNow = true; })
                                  .fork();

            wasConnected = true;
            reportedFailure = false;
            qInfo().noquote() << QString(QLatin1Char('[') + m_logName + QLatin1Char(']')) << "connected to" << m_socketPath;

            while (!m_quit && !disconnectedNow) {
                std::deque<Task> queue;
                {
                    std::lock_guard lock(m_mutex);
                    queue.swap(m_queue);
                }
                for (auto &task : queue) {
                    try {
                        task(tasks);
                    } catch (const kj::Exception &exception) {
                        qWarning().noquote() << QString(QLatin1Char('[') + m_logName + QLatin1Char(']')) << exception.getDescription().cStr();
                    }
                }
                wakeObserver.whenBecomesReadable().exclusiveJoin(disconnect.addBranch()).wait(io.waitScope);
                drainWake();
            }
        } catch (const kj::Exception &exception) {
            if (!reportedFailure)
                qWarning().noquote() << QString(QLatin1Char('[') + m_logName + QLatin1Char(']')) << "no service at" << m_socketPath << ":" << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo().noquote() << QString(QLatin1Char('[') + m_logName + QLatin1Char(']')) << "disconnected, retrying";
        }
        {
            std::lock_guard lock(m_mutex);
            m_queue.clear();
        }
        if (m_quit)
            break;
        io.provider->getTimer().afterDelay(1 * kj::SECONDS).exclusiveJoin(wakeObserver.whenBecomesReadable()).wait(io.waitScope);
        drainWake();
    }
}

} // namespace MaiaNotifications
