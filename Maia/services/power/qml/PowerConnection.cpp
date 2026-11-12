#include "PowerConnection.h"

#include "power.capnp.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>

#include <map>

#include <sys/eventfd.h>
#include <unistd.h>

namespace C = MaiaPower::Contract;

namespace MaiaPower {

// What exists only in the KJ thread, for one connection
struct KjContext {
    C::PowerService::Client service;
    C::PowerControl::Client control;
    kj::TaskSet &tasks;
    // Profile holds by the id holdProfile gave; dropping one releases it
    std::map<int, C::ProfileHold::Client> holds;
};

namespace {

QString toQString(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

BatteryInfo toBattery(C::Battery::Reader b)
{
    BatteryInfo info;
    info.id = toQString(b.getId());
    info.kind = int(b.getKind());
    info.vendor = toQString(b.getVendor());
    info.model = toQString(b.getModel());
    info.present = b.getPresent();
    info.powerSupply = b.getPowerSupply();
    info.percentage = b.getPercentage();
    info.state = int(b.getState());
    info.warningLevel = int(b.getWarningLevel());
    info.timeToEmpty = b.getTimeToEmpty();
    info.timeToFull = b.getTimeToFull();
    info.energyRate = b.getEnergyRate();
    info.capacity = b.getCapacity();
    return info;
}

StatusInfo toStatus(C::PowerStatus::Reader s)
{
    StatusInfo info;
    info.upowerAvailable = s.getUpowerAvailable();
    info.onBattery = s.getOnBattery();
    info.lidPresent = s.getLidPresent();
    info.lidClosed = s.getLidClosed();
    info.summary = toBattery(s.getSummary());
    return info;
}

DisplayInfo toDisplay(C::Display::Reader d)
{
    DisplayInfo info;
    info.id = toQString(d.getId());
    info.kind = int(d.getKind());
    info.device = toQString(d.getDevice());
    info.brightness = d.getBrightness();
    info.rawBrightness = d.getRawBrightness();
    info.rawMaximum = d.getRawMaximum();
    info.minimum = d.getMinimum();
    return info;
}

KeyboardInfo toKeyboard(C::KeyboardBacklight::Reader k)
{
    KeyboardInfo info;
    info.available = k.getAvailable();
    info.brightness = k.getBrightness();
    info.rawBrightness = k.getRawBrightness();
    info.rawMaximum = k.getRawMaximum();
    return info;
}

ProfilesInfo toProfiles(C::Profiles::Reader p)
{
    ProfilesInfo info;
    info.available = p.getAvailable();
    info.active = int(p.getActive());
    for (auto profile : p.getOffered())
        info.offered.append(int(profile));
    info.degraded = int(p.getDegraded());
    for (auto hold : p.getHolds())
        info.holds.append({int(hold.getProfile()), toQString(hold.getReason()), toQString(hold.getApplicationId())});
    return info;
}

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    void taskFailed(kj::Exception &&exception) override
    {
        qWarning() << "[Maia.Power]" << exception.getDescription().cStr();
    }
};

PowerConnection *s_instance = nullptr;

} // namespace

// Called by the service (in the KJ thread); hands the changes to the GUI thread in their order
class Listener final : public C::PowerListener::Server
{
public:
    explicit Listener(PowerConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        auto s = context.getParams().getSnapshot();
        const StatusInfo status = toStatus(s.getStatus());
        QList<BatteryInfo> batteries;
        for (auto b : s.getBatteries())
            batteries.append(toBattery(b));
        QList<DisplayInfo> displays;
        for (auto d : s.getDisplays())
            displays.append(toDisplay(d));
        const KeyboardInfo keyboard = toKeyboard(s.getKeyboard());
        const ProfilesInfo profiles = toProfiles(s.getProfiles());
        m_connection->toGui([c = m_connection, status, batteries, displays, keyboard, profiles] {
            c->applySnapshot(status, batteries, displays, keyboard, profiles);
        });
        return kj::READY_NOW;
    }

    kj::Promise<void> statusChanged(StatusChangedContext context) override
    {
        const StatusInfo status = toStatus(context.getParams().getStatus());
        m_connection->toGui([c = m_connection, status] { c->applyStatus(status); });
        return kj::READY_NOW;
    }

    kj::Promise<void> batteryChanged(BatteryChangedContext context) override
    {
        const BatteryInfo battery = toBattery(context.getParams().getBattery());
        m_connection->toGui([c = m_connection, battery] { c->applyBattery(battery); });
        return kj::READY_NOW;
    }

    kj::Promise<void> batteryRemoved(BatteryRemovedContext context) override
    {
        const QString id = toQString(context.getParams().getId());
        m_connection->toGui([c = m_connection, id] { c->removeBattery(id); });
        return kj::READY_NOW;
    }

    kj::Promise<void> displayChanged(DisplayChangedContext context) override
    {
        const DisplayInfo display = toDisplay(context.getParams().getDisplay());
        m_connection->toGui([c = m_connection, display] { c->applyDisplay(display); });
        return kj::READY_NOW;
    }

    kj::Promise<void> displayRemoved(DisplayRemovedContext context) override
    {
        const QString id = toQString(context.getParams().getId());
        m_connection->toGui([c = m_connection, id] { c->removeDisplay(id); });
        return kj::READY_NOW;
    }

    kj::Promise<void> keyboardChanged(KeyboardChangedContext context) override
    {
        const KeyboardInfo keyboard = toKeyboard(context.getParams().getKeyboard());
        m_connection->toGui([c = m_connection, keyboard] { c->applyKeyboard(keyboard); });
        return kj::READY_NOW;
    }

    kj::Promise<void> profilesChanged(ProfilesChangedContext context) override
    {
        const ProfilesInfo profiles = toProfiles(context.getParams().getProfiles());
        m_connection->toGui([c = m_connection, profiles] { c->applyProfiles(profiles); });
        return kj::READY_NOW;
    }

    kj::Promise<void> event(EventContext context) override
    {
        auto e = context.getParams().getEvent();
        const int kind = int(e.getKind());
        const QString batteryId = toQString(e.getBatteryId());
        const double percentage = e.getPercentage();
        m_connection->toGui([c = m_connection, kind, batteryId, percentage] { Q_EMIT c->event(kind, batteryId, percentage); });
        return kj::READY_NOW;
    }

private:
    PowerConnection *m_connection;
};

PowerConnection::PowerConnection(const QString &socketPath, QObject *parent)
    : QObject(parent)
    , m_socketPath(socketPath)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    m_thread = std::thread([this] { run(); });
}

PowerConnection::~PowerConnection()
{
    m_quit = true;
    wake();
    m_thread.join();
    ::close(m_eventFd);
    if (s_instance == this)
        s_instance = nullptr;
}

PowerConnection *PowerConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new PowerConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString PowerConnection::defaultSocketPath()
{
    const QString explicitPath = qEnvironmentVariable("MAIA_POWER_SOCKET");
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    const QString display = QFileInfo(qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"))).fileName();
    return runtime + QStringLiteral("/maia/power-") + display + QStringLiteral(".sock");
}

// --- GUI thread: the state ---

void PowerConnection::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    Q_EMIT connectedChanged();
}

void PowerConnection::applySnapshot(const StatusInfo &status, const QList<BatteryInfo> &batteries,
                                    const QList<DisplayInfo> &displays, const KeyboardInfo &keyboard,
                                    const ProfilesInfo &profiles)
{
    applyStatus(status);
    m_batteries = batteries;
    Q_EMIT batteriesReset();
    m_displays = displays;
    Q_EMIT displaysReset();
    applyKeyboard(keyboard);
    applyProfiles(profiles);
    setConnected(true);
}

void PowerConnection::applyStatus(const StatusInfo &status)
{
    if (m_status == status)
        return;
    m_status = status;
    Q_EMIT statusChanged();
}

void PowerConnection::applyBattery(const BatteryInfo &battery)
{
    for (int row = 0; row < m_batteries.size(); ++row) {
        if (m_batteries[row].id == battery.id) {
            if (m_batteries[row] == battery)
                return;
            m_batteries[row] = battery;
            Q_EMIT batteryChanged(row);
            return;
        }
    }
    m_batteries.append(battery);
    Q_EMIT batteryAdded(int(m_batteries.size()) - 1);
}

void PowerConnection::removeBattery(const QString &id)
{
    for (int row = 0; row < m_batteries.size(); ++row) {
        if (m_batteries[row].id == id) {
            m_batteries.removeAt(row);
            Q_EMIT batteryRemoved(row);
            return;
        }
    }
}

void PowerConnection::applyDisplay(const DisplayInfo &display)
{
    for (int row = 0; row < m_displays.size(); ++row) {
        if (m_displays[row].id == display.id) {
            if (m_displays[row] == display)
                return;
            m_displays[row] = display;
            Q_EMIT displayChanged(row);
            return;
        }
    }
    m_displays.append(display);
    Q_EMIT displayAdded(int(m_displays.size()) - 1);
}

void PowerConnection::removeDisplay(const QString &id)
{
    for (int row = 0; row < m_displays.size(); ++row) {
        if (m_displays[row].id == id) {
            m_displays.removeAt(row);
            Q_EMIT displayRemoved(row);
            return;
        }
    }
}

void PowerConnection::applyKeyboard(const KeyboardInfo &keyboard)
{
    if (m_keyboard == keyboard)
        return;
    m_keyboard = keyboard;
    Q_EMIT keyboardChanged();
}

void PowerConnection::applyProfiles(const ProfilesInfo &profiles)
{
    if (m_profiles == profiles)
        return;
    m_profiles = profiles;
    Q_EMIT profilesChanged();
}

// --- KJ thread ---

void PowerConnection::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void PowerConnection::post(Task task)
{
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

void PowerConnection::run()
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

            auto service = client.bootstrap().castAs<C::PowerService>();
            // Pipelining: the control capability is usable at once, without waiting for the answer
            KjContext context{service, service.controlRequest().send().getControl(), tasks, {}};

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
            qInfo() << "[Maia.Power] connected to" << m_socketPath;

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
                        qWarning() << "[Maia.Power]" << exception.getDescription().cStr();
                    }
                }
                wakeObserver.whenBecomesReadable().exclusiveJoin(disconnect.addBranch()).wait(io.waitScope);
                drainWake();
            }
            context.holds.clear();
        } catch (const kj::Exception &exception) {
            if (!reportedFailure)
                qWarning() << "[Maia.Power] no power service at" << m_socketPath << ":" << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo() << "[Maia.Power] disconnected, retrying";
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

// --- Requests (GUI thread) ---

namespace {

// The answer of a request with a Result, to requestFinished; copies of the lambdas go to then():
// a named lambda would be kept by reference and be gone when the answer comes
template<typename Promise>
void finish(PowerConnection *connection, KjContext &c, Promise &&promise, const QString &action,
            std::function<void(const QString &, int, const QString &)> report)
{
    auto done = [report, action](auto &&response) {
        auto result = response.getResult();
        report(action, int(result.getError()), toQString(result.getMessage()));
    };
    auto failed = [report, action](kj::Exception &&exception) {
        report(action, int(C::ErrorCode::FAILED), QString::fromUtf8(exception.getDescription().cStr()));
    };
    c.tasks.add(promise.then(kj::cp(done), kj::cp(failed)));
    Q_UNUSED(connection);
}

} // namespace

#define MAIA_POWER_REPORT                                                                                              \
    [this](const QString &action, int error, const QString &message) {                                                 \
        toGui([this, action, error, message] { Q_EMIT requestFinished(action, error, message); });                     \
    }

void PowerConnection::setBrightness(const QString &displayId, double brightness)
{
    if (!m_connected)
        return Q_EMIT requestFinished(QStringLiteral("setBrightness"), int(C::ErrorCode::UNAVAILABLE), QStringLiteral("no power service"));
    post([this, id = displayId.toUtf8(), brightness](KjContext &c) {
        auto request = c.control.setBrightnessRequest();
        request.setDisplayId(id.constData());
        request.setBrightness(brightness);
        finish(this, c, request.send(), QStringLiteral("setBrightness"), MAIA_POWER_REPORT);
    });
}

void PowerConnection::stepBrightness(const QString &displayId, int steps)
{
    if (!m_connected)
        return Q_EMIT requestFinished(QStringLiteral("stepBrightness"), int(C::ErrorCode::UNAVAILABLE), QStringLiteral("no power service"));
    post([this, id = displayId.toUtf8(), steps](KjContext &c) {
        auto request = c.control.stepBrightnessRequest();
        request.setDisplayId(id.constData());
        request.setSteps(steps);
        finish(this, c, request.send(), QStringLiteral("stepBrightness"), MAIA_POWER_REPORT);
    });
}

void PowerConnection::setKeyboardBrightness(double brightness)
{
    if (!m_connected)
        return Q_EMIT requestFinished(QStringLiteral("setKeyboardBrightness"), int(C::ErrorCode::UNAVAILABLE), QStringLiteral("no power service"));
    post([this, brightness](KjContext &c) {
        auto request = c.control.setKeyboardBrightnessRequest();
        request.setBrightness(brightness);
        finish(this, c, request.send(), QStringLiteral("setKeyboardBrightness"), MAIA_POWER_REPORT);
    });
}

void PowerConnection::setProfile(int profile)
{
    if (!m_connected)
        return Q_EMIT requestFinished(QStringLiteral("setProfile"), int(C::ErrorCode::UNAVAILABLE), QStringLiteral("no power service"));
    post([this, profile](KjContext &c) {
        auto request = c.control.setProfileRequest();
        request.setProfile(C::Profile(profile));
        finish(this, c, request.send(), QStringLiteral("setProfile"), MAIA_POWER_REPORT);
    });
}

int PowerConnection::holdProfile(int profile, const QString &reason, const QString &applicationId)
{
    const int id = ++m_nextHold;
    if (!m_connected) {
        QMetaObject::invokeMethod(this, [this, id] { Q_EMIT holdFinished(id, int(C::ErrorCode::UNAVAILABLE), QStringLiteral("no power service")); },
                                  Qt::QueuedConnection);
        return id;
    }
    post([this, id, profile, reason = reason.toUtf8(), app = applicationId.toUtf8()](KjContext &c) {
        auto request = c.control.holdProfileRequest();
        request.setProfile(C::Profile(profile));
        request.setReason(reason.constData());
        request.setApplicationId(app.constData());
        auto promise = request.send();
        // Kept at once (pipelined): releasing it before the answer still releases the hold
        c.holds.emplace(id, promise.getHold());
        auto done = [this, id](auto &&response) {
            auto result = response.getResult();
            const int error = int(result.getError());
            const QString message = toQString(result.getMessage());
            toGui([this, id, error, message] { Q_EMIT holdFinished(id, error, message); });
        };
        auto failed = [this, id](kj::Exception &&exception) {
            const QString message = QString::fromUtf8(exception.getDescription().cStr());
            toGui([this, id, message] { Q_EMIT holdFinished(id, int(C::ErrorCode::FAILED), message); });
        };
        c.tasks.add(promise.then(kj::cp(done), kj::cp(failed)));
    });
    return id;
}

void PowerConnection::releaseProfile(int id)
{
    post([id](KjContext &c) { c.holds.erase(id); });
}

} // namespace MaiaPower
