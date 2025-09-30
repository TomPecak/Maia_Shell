#include "MSessionManager.hpp"
#include <QDBusPendingReply>
#include <QDebug>

MSessionManager::MSessionManager(QObject *parent)
    : QObject(parent)
{
    qDebug() << __PRETTY_FUNCTION__;
    // Connect to the D-Bus interface of the server
    m_dbusInterface = new QDBusInterface(
        "org.maia.SessionService", // Service name
        "/Session",            // Object path
        "org.maia.SessionInterface", // Interface
        QDBusConnection::sessionBus(), // Session D-Bus connection
        this
        );

    if (!m_dbusInterface->isValid()) {
        qDebug() << "[ERROR] Failed to connect to the D-Bus interface!";
    }else{
        qDebug() << "[OK] Valid org.maia.SessionService d-bus";
    }
}

MSessionManager::~MSessionManager()
{
    delete m_dbusInterface;
}

void MSessionManager::logout()
{
    qDebug() << __PRETTY_FUNCTION__;
    if (m_dbusInterface->isValid()) {
        // Asynchronous call to the logout method
        QDBusPendingCall call = m_dbusInterface->asyncCall("logout");
        QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, &MSessionManager::onCallFinished);
    } else {
        qDebug() << "D-Bus is not available for logout!";
    }
}

void MSessionManager::reboot()
{
    qDebug() << __PRETTY_FUNCTION__;
    if (m_dbusInterface->isValid()) {
        // Asynchronous call to the reboot method
        QDBusPendingCall call = m_dbusInterface->asyncCall("reboot");
        QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, &MSessionManager::onCallFinished);
    } else {
        qDebug() << "[ERROR] D-Bus is not available for reboot!";
    }
}

void MSessionManager::poweroff()
{
    qDebug() << __PRETTY_FUNCTION__;
    if (m_dbusInterface->isValid()) {
        // Asynchronous call to the poweroff method
        QDBusPendingCall call = m_dbusInterface->asyncCall("poweroff");
        QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, &MSessionManager::onCallFinished);
    } else {
        qDebug() << "[ERROR] D-Bus is not available for poweroff!";
    }
}

void MSessionManager::onCallFinished(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<> reply = *watcher;
    if (reply.isError()) {
        qDebug() << "[ERROR] D-Bus call error:" << reply.error().message();
    } else {
        //qDebug() << "D-Bus call completed successfully";
    }
    watcher->deleteLater();
}
