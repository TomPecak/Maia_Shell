#include "SessionService.hpp"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QCoreApplication>
#include <QDBusMessage>
#include <QDBusPendingReply>

SessionService::SessionService(QObject *parent)
    : QObject(parent) {
    qDebug() << __PRETTY_FUNCTION__;

    QString dbusAddress = qgetenv("DBUS_SESSION_BUS_ADDRESS");

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

    if(!bus.registerService(u"org.maia.SessionService")){
        qDebug() << "[ERROR] Failed to register D-Bus service";
        return;
    }

    if(!bus.registerObject(u"/Session", this, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qDebug() << "[ERROR] Failed to register D-Bus object.";
    }
}

SessionService::~SessionService() {}

void SessionService::logout() {
    qDebug() << "[D-Bus] Logout received";
    Q_EMIT logoutRequest();
}

void SessionService::reboot() {
    qDebug() << "[D-Bus] Reboot received";
    Q_EMIT rebootRequest();
    executeFreedesktopReboot();
}

void SessionService::poweroff() {
    qDebug() << "[D-Bus] Poweroff received";
    Q_EMIT poweroffRequest();
    executeFreedesktopPoweroff();
}

void SessionService::onCallFinished(QDBusPendingCallWatcher *watcher)
{
    QString operation = watcher->property("operation").toString();
    QDBusPendingReply<> reply = *watcher;
    if (reply.isError()) {
        qDebug() << "Failed to" << operation << ":" << reply.error().message();
    } else {
        qDebug() << operation << "command sent successfully.";
    }
    watcher->deleteLater();
}

void SessionService::executeFreedesktopReboot()
{
    qDebug() << __PRETTY_FUNCTION__;
    QDBusMessage message = QDBusMessage::createMethodCall(
        u"org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "Reboot"
        );
    message << true;

    QDBusPendingCall pendingCall = QDBusConnection::systemBus().asyncCall(message);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pendingCall, this);
    watcher->setProperty("operation", u"reboot");
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &SessionService::onCallFinished);
}

void SessionService::executeFreedesktopPoweroff()
{
    qDebug() << __PRETTY_FUNCTION__;
    QDBusMessage message = QDBusMessage::createMethodCall(
        u"org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
        "PowerOff"
        );
    message << true;

    QDBusPendingCall pendingCall = QDBusConnection::systemBus().asyncCall(message);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pendingCall, this);
    watcher->setProperty("operation", "power off");
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &SessionService::onCallFinished);
}
