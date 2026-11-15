#include "SettingsConnection.h"

#include <QCoreApplication>
#include <QDebug>

namespace MaiaNotifications {

namespace {
SettingsConnection *s_instance = nullptr;
}

// The service's calls (KJ thread): read into Qt values here, applied in the GUI thread
class SettingsListenerImpl final : public C::SettingsListener::Server
{
public:
    explicit SettingsListenerImpl(SettingsConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> settingsChanged(SettingsChangedContext context) override
    {
        SettingsData settings = readSettings(context.getParams().getSettings());
        m_connection->toGui([c = m_connection, settings = std::move(settings)] { c->apply(settings); });
        return kj::READY_NOW;
    }

private:
    SettingsConnection *m_connection;
};

SettingsConnection::SettingsConnection(const QString &socketPath, QObject *parent)
    : ServiceLink(socketPath, QStringLiteral("Maia.Notifications.Settings"), parent)
{
    start();
}

SettingsConnection::~SettingsConnection()
{
    stop();
    if (s_instance == this)
        s_instance = nullptr;
}

SettingsConnection *SettingsConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new SettingsConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString SettingsConnection::defaultSocketPath()
{
    return socketPathFor("MAIA_NOTIFICATIONS_SETTINGS_SOCKET", QStringLiteral("notifications-settings"));
}

void SettingsConnection::connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks)
{
    m_service = bootstrap.castAs<C::NotificationSettings>();
    auto watch = m_service->watchRequest();
    watch.setListener(kj::heap<SettingsListenerImpl>(this));
    auto watched = watch.send();
    // Kept for the whole connection: releasing it would stop the listener
    m_subscription = watched.getSubscription();
    tasks.add(watched.ignoreResult());
}

void SettingsConnection::disconnected()
{
    m_subscription.reset();
    m_service.reset();
}

void SettingsConnection::apply(const SettingsData &settings)
{
    m_settings = settings;
    m_hasSettings = true;
    Q_EMIT settingsChanged();
}

void SettingsConnection::setDoNotDisturb(bool enabled, qint64 until)
{
    post([this, enabled, until](kj::TaskSet &tasks) {
        if (!m_service)
            return;
        auto call = m_service->setDoNotDisturbRequest();
        call.setEnabled(enabled);
        call.setUntil(until);
        tasks.add(call.send().ignoreResult());
    });
}

void SettingsConnection::setLockScreenNotifications(bool enabled)
{
    post([this, enabled](kj::TaskSet &tasks) {
        if (!m_service)
            return;
        auto call = m_service->setLockScreenNotificationsRequest();
        call.setEnabled(enabled);
        tasks.add(call.send().ignoreResult());
    });
}

void SettingsConnection::setAppEnabled(const QString &key, bool enabled)
{
    post([this, key, enabled](kj::TaskSet &tasks) {
        if (!m_service)
            return;
        auto call = m_service->setAppEnabledRequest();
        call.setKey(key.toUtf8().constData());
        call.setEnabled(enabled);
        auto done = [key](auto &&response) {
            auto result = response.getResult();
            if (result.getError() != C::ErrorCode::NONE)
                qDebug() << "[Maia.Notifications.Settings] setAppEnabled" << key << "refused:" << toQString(result.getMessage());
        };
        tasks.add(call.send().then(kj::cp(done)));
    });
}

} // namespace MaiaNotifications
