#include "MSessionManager.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>

MSessionManager::MSessionManager(QObject *parent)
    : QObject(parent)
{
    qDebug() << __PRETTY_FUNCTION__;
    queryLogind(QStringLiteral("CanSuspend"), &MSessionManager::m_canSuspend);
    queryLogind(QStringLiteral("CanReboot"), &MSessionManager::m_canReboot);
    queryLogind(QStringLiteral("CanPowerOff"), &MSessionManager::m_canPowerOff);
}

void MSessionManager::logout()
{
    callSessionService(QStringLiteral("logout"));
}

void MSessionManager::suspend()
{
    callSessionService(QStringLiteral("suspend"));
}

void MSessionManager::reboot()
{
    callSessionService(QStringLiteral("reboot"));
}

void MSessionManager::poweroff()
{
    callSessionService(QStringLiteral("poweroff"));
}

void MSessionManager::callSessionService(const QString &method)
{
    qDebug() << "[Session]" << method;
    // A plain message rather than a QDBusInterface: QDBusInterface checks the service once, when it
    // is created, and stays unusable if the server registered it later (e.g. in a proxy window
    // process that started first)
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.maia.SessionService"),
        QStringLiteral("/Session"),
        QStringLiteral("org.maia.SessionInterface"),
        method);

    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [method](QDBusPendingCallWatcher *call) {
        const QDBusPendingReply<> reply = *call;
        if (reply.isError())
            qDebug() << "[ERROR] session action" << method << "failed:" << reply.error().message();
        call->deleteLater();
    });
}

void MSessionManager::queryLogind(const QString &method, bool MSessionManager::*flag)
{
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        method);

    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, method, flag](QDBusPendingCallWatcher *call) {
        const QDBusPendingReply<QString> reply = *call;
        call->deleteLater();
        if (reply.isError()) {
            qDebug() << "[Session] logind" << method << "not answered:" << reply.error().message();
            return;
        }
        // "yes", "challenge" (allowed after a password), "no", "na" (not supported)
        const QString answer = reply.value();
        const bool allowed = answer == QLatin1String("yes") || answer == QLatin1String("challenge");
        if (this->*flag != allowed) {
            this->*flag = allowed;
            Q_EMIT capabilitiesChanged();
        }
    });
}
