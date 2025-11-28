#include "MLocaleSettings.hpp"
#include <QDebug>
#include <QDBusMessage>
#include <QDBusPendingReply>
#include <QDBusVariant>

MLocaleSettings::MLocaleSettings(QObject *parent)
    : QObject(parent)
    , m_twentyFourTime(false) // Default value
    , m_dbusInterface(nullptr)
{
    // 1. Service Watcher (Handles Server Restarts)
    m_watcher = new QDBusServiceWatcher(ServiceName,
                                        QDBusConnection::sessionBus(),
                                        QDBusServiceWatcher::WatchForRegistration |
                                            QDBusServiceWatcher::WatchForUnregistration,
                                        this);

    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &MLocaleSettings::onServiceRegistered);
    connect(m_watcher, &QDBusServiceWatcher::serviceUnregistered, this, &MLocaleSettings::onServiceUnregistered);

    // 2. Initialize Interface (Used to check validity)
    m_dbusInterface = new QDBusInterface(ServiceName,
                                         ObjectPath,
                                         Interface,
                                         QDBusConnection::sessionBus(),
                                         this);

    // 3. Connect to D-Bus Signal (For real-time updates from Server)
    QDBusConnection::sessionBus().connect(
        ServiceName,
        ObjectPath,
        Interface,
        QStringLiteral("twentyFourTimeChanged"),
        this,
        SLOT(onRemoteChanged(bool)) // Note: Keeping string-based slot for D-Bus signals is often safest for type matching
        );

    // 4. Initial Sync if service is already running
    if (m_dbusInterface->isValid()) {
        syncWithServer();
    }
}

bool MLocaleSettings::twentyFourTime() const
{
    return m_twentyFourTime;
}

void MLocaleSettings::setTwentyFourTime(bool newTwentyFourTime)
{
    if (m_twentyFourTime == newTwentyFourTime)
        return;

    // --- OPTIMISTIC UI UPDATE ---
    // Update local state immediately so the UI feels instant.
    bool oldTwentyFourTime = m_twentyFourTime;
    m_twentyFourTime = newTwentyFourTime;
    emit twentyFourTimeChanged();

    // Check if connected
    if (!m_dbusInterface || !m_dbusInterface->isValid()) {
        qWarning() << "MLocaleSettings: D-Bus service not available. Reverting.";
        m_twentyFourTime = oldTwentyFourTime;
        emit twentyFourTimeChanged();
        return;
    }

    // --- ASYNCHRONOUS SET ---
    // We construct a message to org.freedesktop.DBus.Properties.Set
    QDBusMessage msg = QDBusMessage::createMethodCall(
        ServiceName,
        ObjectPath,
        PropertiesInterface,
        QStringLiteral("Set")
        );

    // Arguments: Interface Name, Property Name, New Value (wrapped in QDBusVariant)
    msg << Interface
        << QStringLiteral("twentyFourTime")
        << QVariant::fromValue(QDBusVariant(newTwentyFourTime));

    // Send Async
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    // Handle the result (check for errors)
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, oldTwentyFourTime](QDBusPendingCallWatcher *watcher) {
                QDBusPendingReply<> reply = *watcher;
                if (reply.isError()) {
                    qWarning() << "MLocaleSettings: Failed to set remote property:" << reply.error().message();

                    // Revert local state on error
                    if (m_twentyFourTime != oldTwentyFourTime) {
                        m_twentyFourTime = oldTwentyFourTime;
                        emit twentyFourTimeChanged();
                    }
                } else {
                    qDebug() << "MLocaleSettings: Successfully set property on server.";
                }
                watcher->deleteLater();
            });
}

void MLocaleSettings::syncWithServer()
{
    // --- ASYNCHRONOUS GET ---
    QDBusMessage msg = QDBusMessage::createMethodCall(
        ServiceName,
        ObjectPath,
        PropertiesInterface,
        QStringLiteral("Get")
        );

    msg << Interface << QStringLiteral("twentyFourTime");

    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *watcher) {
                QDBusPendingReply<QVariant> reply = *watcher;

                if (!reply.isError()) {
                    // The DBus Property Get returns a QDBusVariant, which contains a QVariant
                    // Note: Depending on the Qt version and DBus structure, strictly typing this helps.
                    // Usually `Get` returns a QDBusVariant.
                    QDBusVariant dbusVar = qdbus_cast<QDBusVariant>(reply.argumentAt(0));
                    bool remoteValue = dbusVar.variant().toBool();

                    if (m_twentyFourTime != remoteValue) {
                        qDebug() << "[Client] Sync: Local updated from server:" << remoteValue;
                        m_twentyFourTime = remoteValue;
                        emit twentyFourTimeChanged();
                    }
                } else {
                    qWarning() << "[Client] Sync failed:" << reply.error().message();
                }
                watcher->deleteLater();
            });
}

void MLocaleSettings::onRemoteChanged(bool value)
{
    // Handle signal from Server (Server -> Client)
    if (m_twentyFourTime != value) {
        qDebug() << "[Client] Remote signal received:" << value;
        m_twentyFourTime = value;
        emit twentyFourTimeChanged();
    }
}

void MLocaleSettings::onServiceRegistered(const QString &service)
{
    Q_UNUSED(service);
    qDebug() << "[Client] Service registered (re)started. Syncing...";
    // When service appears, we sync the state to make sure we match the server
    syncWithServer();
}

void MLocaleSettings::onServiceUnregistered(const QString &service)
{
    Q_UNUSED(service);
    qDebug() << "[Client] Service lost.";
}
