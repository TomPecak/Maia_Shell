#include "SessionService.hpp"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QCoreApplication>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QStringLiteral>

SessionService::SessionService(QObject *parent)
    : QObject(parent)
    , m_nestedSession(qEnvironmentVariable("MAIA_NESTED_SESSION") == QLatin1String("1")) {
    qDebug() << __PRETTY_FUNCTION__;

    QString dbusAddress = QString::fromUtf8(qgetenv("DBUS_SESSION_BUS_ADDRESS"));

    if (!dbusAddress.isEmpty()) {
        //qDebug() << "DBUS_SESSION_BUS_ADDRESS:" << dbusAddress;
    } else {
        qDebug() << "[Warning] DBUS_SESSION_BUS_ADDRESS is not set.";
    }

    // Register the object and its methods on D-Bus
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (bus.isConnected()) {
        //qDebug() << "Session bus is connected. Name:" << bus.baseService();
        //qDebug() << "Session bus connection name:" << bus.name();
    } else {
        qDebug() << "[Warning] Session bus is not connected.";
    }

    if(!bus.registerService(QStringLiteral("org.maia.SessionService"))){
        qDebug() << "[ERROR] Failed to register D-Bus service";
        return;
    }

    if(!bus.registerObject(QStringLiteral("/Session"), this, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qDebug() << "[ERROR] Failed to register D-Bus object.";
    }
}

SessionService::~SessionService() {}

void SessionService::logout() {
    qDebug() << "[D-Bus] Logout received";
    Q_EMIT logoutRequest();
}

void SessionService::suspend() {
    qDebug() << "[D-Bus] Suspend received";
    Q_EMIT suspendRequest();
    callLogind(QStringLiteral("Suspend"));
}

void SessionService::reboot() {
    qDebug() << "[D-Bus] Reboot received";
    Q_EMIT rebootRequest();
    callLogind(QStringLiteral("Reboot"));
}

void SessionService::poweroff() {
    qDebug() << "[D-Bus] Poweroff received";
    Q_EMIT poweroffRequest();
    callLogind(QStringLiteral("PowerOff"));
}

void SessionService::callLogind(const QString &method)
{
    if (m_nestedSession) {
        qDebug() << "[Session] nested session: logind" << method << "not called (it would act on the real machine)";
        return;
    }

    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.login1"),
        QStringLiteral("/org/freedesktop/login1"),
        QStringLiteral("org.freedesktop.login1.Manager"),
        method
        );
    message << true; // interactive

    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [method](QDBusPendingCallWatcher *call) {
        const QDBusPendingReply<> reply = *call;
        if (reply.isError())
            qDebug() << "[ERROR] logind" << method << "failed:" << reply.error().message();
        else
            qDebug() << "logind" << method << "accepted";
        call->deleteLater();
    });
}
