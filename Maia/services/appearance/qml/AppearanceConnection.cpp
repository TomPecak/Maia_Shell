#include "AppearanceConnection.h"

#include "appearance.capnp.h"
#include "decorations.capnp.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>

#include <QDebug>
#include <QDir>
#include <QFileInfo>

#include <map>
#include <string>

#include <sys/eventfd.h>
#include <unistd.h>

namespace C = MaiaAppearance::Contract;

namespace MaiaAppearance {

namespace {

// The enumerations of AppearanceTypes.h are those of the contract, in the same order
static_assert(int(C::Engine::WAYFIRE) == int(Appearance::Engine::Wayfire));
static_assert(int(C::Origin::USER) == int(Appearance::Origin::User));
static_assert(int(C::BorderSize::OVERSIZED) == int(Appearance::BorderSize::Oversized));
static_assert(int(C::ErrorCode::ALREADY_EXISTS) == int(Appearance::ErrorCode::AlreadyExists));

template<typename To, typename From>
To as(From value)
{
    return static_cast<To>(static_cast<int>(value));
}

QString text(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

ThemeData toTheme(C::Theme::Reader r)
{
    return ThemeData{text(r.getId()),          as<Appearance::Engine>(r.getEngine()), text(r.getName()),
                     text(r.getDescription()), text(r.getAuthor()),                   as<Appearance::Origin>(r.getOrigin()),
                     r.getAvailable(),         text(r.getUnavailableReason()),        text(r.getPath())};
}

QList<ThemeData> toThemes(capnp::List<C::Theme>::Reader list)
{
    QList<ThemeData> themes;
    for (auto theme : list)
        themes.append(toTheme(theme));
    return themes;
}

CurrentData toCurrent(C::Current::Reader r)
{
    return CurrentData{text(r.getThemeId()), as<Appearance::BorderSize>(r.getBorderSize()), r.getConfirmed(), text(r.getFrontend())};
}

CapabilitiesData toCapabilities(C::Capabilities::Reader r)
{
    CapabilitiesData capabilities{text(r.getCompositor()), {}, r.getBorderSizes(), r.getInstall()};
    for (auto engine : r.getEngines())
        capabilities.engines.append(as<Appearance::Engine>(engine));
    return capabilities;
}

Result toResult(C::Result::Reader r)
{
    return Result{as<Appearance::ErrorCode>(r.getError()), text(r.getMessage())};
}

Result failure(const kj::Exception &exception)
{
    return Result{Appearance::ErrorCode::Unavailable, QString::fromUtf8(exception.getDescription().cStr())};
}

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    void taskFailed(kj::Exception &&exception) override
    {
        qWarning() << "[Maia.Appearance]" << exception.getDescription().cStr();
    }
};

} // namespace

// What exists only in the KJ thread, for one connection
struct KjContext {
    C::Decorations::Client decorations;
    kj::TaskSet &tasks;
    std::map<int, C::FrontendActivation::Client> activations;
};

// Called by the service (in the KJ thread); hands the changes to the GUI thread in their order
class Listener final : public C::DecorationsListener::Server
{
public:
    explicit Listener(AppearanceConnection *connection)
        : m_c(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        auto themes = toThemes(context.getParams().getThemes());
        auto current = toCurrent(context.getParams().getCurrent());
        m_c->toGui([c = m_c, themes, current] {
            c->applyThemes(themes);
            c->applyCurrent(current);
            c->setConnected(true);
        });
        return kj::READY_NOW;
    }

    kj::Promise<void> themesChanged(ThemesChangedContext context) override
    {
        auto themes = toThemes(context.getParams().getThemes());
        m_c->toGui([c = m_c, themes] { c->applyThemes(themes); });
        return kj::READY_NOW;
    }

    kj::Promise<void> currentChanged(CurrentChangedContext context) override
    {
        auto current = toCurrent(context.getParams().getCurrent());
        m_c->toGui([c = m_c, current] { c->applyCurrent(current); });
        return kj::READY_NOW;
    }

private:
    AppearanceConnection *m_c;
};

namespace {

void activate(KjContext &context, int handle, const std::string &frontend, const std::string &defaultThemeId)
{
    auto request = context.decorations.activateFrontendRequest();
    request.setFrontend(frontend.c_str());
    request.setDefaultThemeId(defaultThemeId.c_str());
    auto sent = request.send();
    // Pipelining: the activation lives while this capability is kept
    context.activations.insert_or_assign(handle, sent.getActivation());
    context.tasks.add(sent.then([frontend](auto &&response) {
        auto result = toResult(response.getResult());
        if (result.error != Appearance::ErrorCode::None)
            qWarning() << "[Maia.Appearance]" << frontend.c_str() << "decoration:" << result.message;
    }));
}

} // namespace

AppearanceConnection::AppearanceConnection(const QString &socketPath, QObject *parent)
    : AppearanceSource(parent)
    , m_socketPath(socketPath)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    m_thread = std::thread([this] { run(); });
}

AppearanceConnection::~AppearanceConnection()
{
    m_quit = true;
    wake();
    m_thread.join();
    ::close(m_eventFd);
}

QString AppearanceConnection::defaultSocketPath()
{
    const QString explicitPath = qEnvironmentVariable("MAIA_APPEARANCE_SOCKET");
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    const QString display = QFileInfo(qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"))).fileName();
    return runtime + QStringLiteral("/maia/appearance-") + display + QStringLiteral(".sock");
}

void AppearanceConnection::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void AppearanceConnection::post(Task task, const Callback &done)
{
    if (!m_live) {
        if (done)
            done(unavailable());
        return;
    }
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

void AppearanceConnection::run()
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
            auto address = io.provider->getNetwork().parseAddress(kj::str("unix:", m_socketPath.toUtf8().constData())).wait(io.waitScope);
            auto stream = address->connect().wait(io.waitScope);
            capnp::TwoPartyClient client(*stream);
            kj::TaskSet tasks(errors);

            auto service = client.bootstrap().castAs<C::AppearanceService>();
            // Pipelining: usable at once, without waiting for the answers
            KjContext context{service.decorationsRequest().send().getDecorations(), tasks, {}};

            tasks.add(context.decorations.capabilitiesRequest().send().then([this](auto &&response) {
                auto capabilities = toCapabilities(response.getCapabilities());
                toGui([this, capabilities] { applyCapabilities(capabilities); });
            }));
            auto watch = context.decorations.watchRequest();
            watch.setListener(kj::heap<Listener>(this));
            auto watched = watch.send();
            // Kept for the whole connection: releasing it would stop the listener
            auto subscription = watched.getSubscription();
            tasks.add(watched.ignoreResult());

            {
                std::lock_guard lock(m_mutex);
                for (auto it = m_frontends.cbegin(); it != m_frontends.cend(); ++it)
                    activate(context, it.key(), it.value().first.toStdString(), it.value().second.toStdString());
            }

            bool disconnected = false;
            auto disconnect = client.onDisconnect().then([&] { disconnected = true; }, [&](kj::Exception &&) { disconnected = true; }).fork();

            wasConnected = true;
            m_live = true;
            reportedFailure = false;
            qInfo() << "[Maia.Appearance] connected to" << m_socketPath;

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
                        qWarning() << "[Maia.Appearance]" << exception.getDescription().cStr();
                    }
                }
            }
            m_live = false;
        } catch (const kj::Exception &exception) {
            m_live = false;
            if (!reportedFailure)
                qWarning() << "[Maia.Appearance] no appearance service at" << m_socketPath << ":" << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo() << "[Maia.Appearance] disconnected, retrying";
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

// Sends a request with a Result and hands it to `done` in the GUI thread
template<typename Request, typename ToGui>
void sendResult(KjContext &context, Request request, AppearanceSource::Callback done, ToGui toGui)
{
    context.tasks.add(request.send().then(
        [done, toGui](auto &&response) {
            auto result = toResult(response.getResult());
            if (done)
                toGui([done, result] { done(result); });
        },
        [done, toGui](kj::Exception &&exception) {
            auto result = failure(exception);
            if (done)
                toGui([done, result] { done(result); });
        }));
}

} // namespace

void AppearanceConnection::setTheme(const QString &id, Callback done)
{
    post([this, id = id.toStdString(), done](KjContext &c) {
        auto request = c.decorations.setRequest();
        request.setThemeId(id.c_str());
        sendResult(c, kj::mv(request), done, [this](auto f) { toGui(std::move(f)); });
    }, done);
}

void AppearanceConnection::setBorderSize(Appearance::BorderSize size, Callback done)
{
    post([this, size, done](KjContext &c) {
        auto request = c.decorations.setBorderSizeRequest();
        request.setSize(as<C::BorderSize>(size));
        sendResult(c, kj::mv(request), done, [this](auto f) { toGui(std::move(f)); });
    }, done);
}

void AppearanceConnection::install(const QString &path, IdCallback done)
{
    if (!m_live) {
        if (done)
            done(unavailable(), {});
        return;
    }
    post([this, path = path.toStdString(), done](KjContext &c) {
        auto request = c.decorations.installRequest();
        request.setPath(path.c_str());
        c.tasks.add(request.send().then(
            [this, done](auto &&response) {
                auto result = toResult(response.getResult());
                auto id = text(response.getThemeId());
                if (done)
                    toGui([done, result, id] { done(result, id); });
            },
            [this, done](kj::Exception &&exception) {
                auto result = failure(exception);
                if (done)
                    toGui([done, result] { done(result, {}); });
            }));
    });
}

void AppearanceConnection::remove(const QString &id, Callback done)
{
    post([this, id = id.toStdString(), done](KjContext &c) {
        auto request = c.decorations.removeRequest();
        request.setThemeId(id.c_str());
        sendResult(c, kj::mv(request), done, [this](auto f) { toGui(std::move(f)); });
    }, done);
}

void AppearanceConnection::refresh()
{
    post([](KjContext &c) { c.tasks.add(c.decorations.refreshRequest().send().ignoreResult()); });
}

void AppearanceConnection::activateFrontend(int handle, const QString &frontend, const QString &defaultThemeId)
{
    {
        std::lock_guard lock(m_mutex);
        m_frontends.insert(handle, {frontend, defaultThemeId});
    }
    // Without a connection it is sent when one comes
    post([handle, frontend = frontend.toStdString(), defaultThemeId = defaultThemeId.toStdString()](KjContext &c) {
        activate(c, handle, frontend, defaultThemeId);
    });
}

void AppearanceConnection::deactivateFrontend(int handle)
{
    {
        std::lock_guard lock(m_mutex);
        m_frontends.remove(handle);
    }
    post([handle](KjContext &c) { c.activations.erase(handle); });
}

} // namespace MaiaAppearance
