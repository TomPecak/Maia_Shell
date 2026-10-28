#include "ServiceConnection.h"

#include "windows.capnp.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QPointer>

#include <sys/eventfd.h>
#include <unistd.h>

namespace C = MaiaWindows::Contract;

namespace MaiaWindows {

// The bits of WindowInfo.h must be those of the contract
static_assert(Active == C::STATE_ACTIVE && Minimized == C::STATE_MINIMIZED && Maximized == C::STATE_MAXIMIZED
              && Fullscreen == C::STATE_FULLSCREEN && KeepAbove == C::STATE_KEEP_ABOVE
              && KeepBelow == C::STATE_KEEP_BELOW && DemandsAttention == C::STATE_DEMANDS_ATTENTION
              && SkipTaskbar == C::STATE_SKIP_TASKBAR && Resizable == C::STATE_RESIZABLE
              && SkipSwitcher == C::STATE_SKIP_SWITCHER);
static_assert(CanActivate == C::CAP_ACTIVATE && HasBitmapIcons == C::CAP_BITMAP_ICONS && CanLaunch == C::CAP_LAUNCH);

// What exists only in the KJ thread, for one connection
struct KjContext {
    C::WindowService::Client service;
    C::WindowControl::Client control;
    kj::TaskSet &tasks;
};

namespace {

QString toQString(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

WindowInfo toWindowInfo(C::Window::Reader w)
{
    WindowInfo info;
    info.id = toQString(w.getId());
    info.title = toQString(w.getTitle());
    info.appId = toQString(w.getAppId());
    info.rawAppId = toQString(w.getRawAppId());
    info.appName = toQString(w.getAppName());
    info.genericName = toQString(w.getGenericName());
    info.iconName = toQString(w.getIconName());
    info.iconSerial = w.getIconSerial();
    info.launcherUrl = toQString(w.getLauncherUrl());
    info.pid = w.getPid();
    info.states = w.getStates();
    const auto g = w.getGeometry();
    info.geometry = QRect(g.getX(), g.getY(), int(g.getWidth()), int(g.getHeight()));
    for (auto desktop : w.getVirtualDesktops())
        info.virtualDesktops.append(toQString(desktop));
    info.parentId = toQString(w.getParentId());
    info.lastActivated = w.getLastActivated();
    info.canLaunchNewInstance = w.getCanLaunchNewInstance();
    return info;
}

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    void taskFailed(kj::Exception &&exception) override
    {
        qWarning() << "[Maia.Windows]" << exception.getDescription().cStr();
    }
};

ServiceConnection *s_instance = nullptr;

} // namespace

// Called by the service (in the KJ thread); hands the changes to the GUI thread in their order
class Listener final : public C::WindowListener::Server
{
public:
    explicit Listener(ServiceConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        QList<WindowInfo> windows;
        for (auto window : context.getParams().getWindows())
            windows.append(toWindowInfo(window));
        m_connection->toGui([c = m_connection, windows] { c->applySnapshot(windows); });
        return kj::READY_NOW;
    }

    kj::Promise<void> added(AddedContext context) override
    {
        auto window = toWindowInfo(context.getParams().getWindow());
        m_connection->toGui([c = m_connection, window] { c->upsert(window); });
        return kj::READY_NOW;
    }

    kj::Promise<void> changed(ChangedContext context) override
    {
        auto window = toWindowInfo(context.getParams().getWindow());
        m_connection->toGui([c = m_connection, window] { c->upsert(window); });
        return kj::READY_NOW;
    }

    kj::Promise<void> removed(RemovedContext context) override
    {
        auto id = toQString(context.getParams().getId());
        m_connection->toGui([c = m_connection, id] { c->remove(id); });
        return kj::READY_NOW;
    }

private:
    ServiceConnection *m_connection;
};

ServiceConnection::ServiceConnection(const QString &socketPath, QObject *parent)
    : WindowSource(parent)
    , m_socketPath(socketPath)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    m_thread = std::thread([this] { run(); });
}

ServiceConnection::~ServiceConnection()
{
    m_quit = true;
    wake();
    m_thread.join();
    ::close(m_eventFd);
    if (s_instance == this)
        s_instance = nullptr;
}

ServiceConnection *ServiceConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new ServiceConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString ServiceConnection::defaultSocketPath()
{
    const QString explicitPath = qEnvironmentVariable("MAIA_WINDOWS_SOCKET");
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    QString display = qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"));
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    display = QFileInfo(display).fileName();
    return runtime + QStringLiteral("/maia/windows-") + display + QStringLiteral(".sock");
}

void ServiceConnection::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void ServiceConnection::post(Task task)
{
    if (!isConnected())
        return;
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

void ServiceConnection::run()
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

            auto service = client.bootstrap().castAs<C::WindowService>();
            // Pipelining: the control capability is usable at once, without waiting for the answer
            KjContext context{service, service.controlRequest().send().getControl(), tasks};

            auto watch = service.watchRequest();
            watch.setListener(kj::heap<Listener>(this));
            auto watched = watch.send();
            // Kept for the whole connection: releasing it would stop the listener
            auto subscription = watched.getSubscription();
            tasks.add(watched.ignoreResult());

            // Connected for the GUI once the service answered (with what it can do)
            tasks.add(service.infoRequest().send().then([this](auto &&response) {
                const quint32 capabilities = response.getCapabilities();
                toGui([this, capabilities] { setConnected(true, capabilities); });
            }));

            bool disconnected = false;
            auto disconnect = client.onDisconnect()
                                  .then([&] { disconnected = true; }, [&](kj::Exception &&) { disconnected = true; })
                                  .fork();

            wasConnected = true;
            reportedFailure = false;
            qInfo() << "[Maia.Windows] connected to" << m_socketPath;

            while (!m_quit && !disconnected) {
                wakeObserver.whenBecomesReadable().exclusiveJoin(disconnect.addBranch()).wait(io.waitScope);
                drainWake();
                std::deque<Task> queue;
                {
                    std::lock_guard lock(m_mutex);
                    queue.swap(m_queue);
                }
                for (auto &task : queue) {
                    try {
                        task(context);
                    } catch (const kj::Exception &exception) {
                        qWarning() << "[Maia.Windows]" << exception.getDescription().cStr();
                    }
                }
            }
        } catch (const kj::Exception &exception) {
            if (!reportedFailure)
                qWarning() << "[Maia.Windows] no window service at" << m_socketPath << ":"
                           << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo() << "[Maia.Windows] disconnected, retrying";
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

// --- Commands (GUI thread) ---

namespace {

// A request on a window of the control capability, by id
template<typename Request>
void sendWithId(KjContext &context, Request request, const QByteArray &id)
{
    request.setId(id.constData());
    context.tasks.add(request.send().ignoreResult());
}

} // namespace

void ServiceConnection::activate(const QString &id)
{
    post([id = id.toUtf8()](KjContext &c) { sendWithId(c, c.control.activateRequest(), id); });
}

void ServiceConnection::close(const QString &id)
{
    post([id = id.toUtf8()](KjContext &c) { sendWithId(c, c.control.closeRequest(), id); });
}

void ServiceConnection::setState(const QString &id, State flag, bool on)
{
    post([id = id.toUtf8(), flag, on](KjContext &c) {
        auto send = [&](auto request, auto set) {
            request.setId(id.constData());
            set(request);
            c.tasks.add(request.send().ignoreResult());
        };
        switch (flag) {
        case Minimized:
            send(c.control.setMinimizedRequest(), [on](auto &r) { r.setMinimized(on); });
            break;
        case Maximized:
            send(c.control.setMaximizedRequest(), [on](auto &r) { r.setMaximized(on); });
            break;
        case Fullscreen:
            send(c.control.setFullscreenRequest(), [on](auto &r) { r.setFullscreen(on); });
            break;
        case KeepAbove:
            send(c.control.setKeepAboveRequest(), [on](auto &r) { r.setKeepAbove(on); });
            break;
        case KeepBelow:
            send(c.control.setKeepBelowRequest(), [on](auto &r) { r.setKeepBelow(on); });
            break;
        default:
            qWarning() << "[Maia.Windows] state" << flag << "cannot be set";
        }
    });
}

void ServiceConnection::requestMove(const QString &id)
{
    post([id = id.toUtf8()](KjContext &c) { sendWithId(c, c.control.requestMoveRequest(), id); });
}

void ServiceConnection::requestResize(const QString &id)
{
    post([id = id.toUtf8()](KjContext &c) { sendWithId(c, c.control.requestResizeRequest(), id); });
}

void ServiceConnection::launchNewInstance(const QString &id)
{
    post([id = id.toUtf8()](KjContext &c) { sendWithId(c, c.control.launchNewInstanceRequest(), id); });
}

void ServiceConnection::launch(const QString &launcherUrl)
{
    post([url = launcherUrl.toUtf8()](KjContext &c) {
        auto request = c.control.launchRequest();
        request.setLauncherUrl(url.constData());
        c.tasks.add(request.send().ignoreResult());
    });
}

void ServiceConnection::fetchIcon(const QString &id, quint32 serial)
{
    post([this, id, serial](KjContext &c) {
        auto request = c.service.iconRequest();
        request.setId(id.toUtf8().constData());
        c.tasks.add(request.send().then(
            [this, id](auto &&response) {
                const auto data = response.getData();
                QByteArray bytes(reinterpret_cast<const char *>(data.begin()), qsizetype(data.size()));
                const quint32 serial = response.getSerial();
                toGui([this, id, serial, bytes] { deliverIcon(id, serial, bytes); });
            },
            [this, id, serial](kj::Exception &&) {
                // No icon this time; the window keeps its named icon
                toGui([this, id, serial] { deliverIcon(id, serial, {}); });
            }));
    });
}

} // namespace MaiaWindows
