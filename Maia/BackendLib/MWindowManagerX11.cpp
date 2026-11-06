#include "MWindowManagerX11.hpp"

#include <QDBusPendingReply>

MWindowManagerX11::MWindowManagerX11(QObject *parent)
{
    qDebug() << __PRETTY_FUNCTION__;

    m_dbusInterface = new QDBusInterface(QStringLiteral("org.maia.WindowManagerX11Service"),
                                         QStringLiteral("/WindowManagerX11"),
                                         QStringLiteral("org.maia.WindowManagerX11Interface"),
                                         QDBusConnection::sessionBus(),
                                         this);

    if (!m_dbusInterface->isValid()) {
        qDebug() << "[ERROR] Failed to connect to the D-Bus interface!";
    } else {
        qDebug() << "[OK] Valid org.maia.WindowManagerX11Service d-bus";
    }
}

MWindowManagerX11::~MWindowManagerX11()
{
    delete m_dbusInterface;
}

void MWindowManagerX11::reconfigure()
{
    qDebug() << __PRETTY_FUNCTION__;

    if (!m_dbusInterface->isValid()) {
        qDebug() << "D-Bus is not available for reconfigure!";
        return;
    }

    QDBusPendingCall call = m_dbusInterface->asyncCall(QStringLiteral("reconfigure"));
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &MWindowManagerX11::onCallFinished);
}

void MWindowManagerX11::unloadEffect(const QString &effectName)
{
    //qDebug() << __PRETTY_FUNCTION__;

    if (!m_dbusInterface->isValid()) {
        qDebug() << "D-Bus is not available for unloadEffect!";
        return;
    }

    QDBusPendingCall call = m_dbusInterface->asyncCall(QStringLiteral("unloadEffect"), effectName);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &MWindowManagerX11::onCallFinished);
}

void MWindowManagerX11::onCallFinished(QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<> reply = *watcher;
    if (reply.isError()) {
        qDebug() << "D-Bus call error:" << reply.error().message();
    } else {
        //qDebug() << "D-Bus call completed successfully";
    }
    watcher->deleteLater();
}
