#include "MWindowManagerX11.hpp"

#include <QDBusPendingReply>

MWindowManagerX11::MWindowManagerX11(QObject *parent)
{
    qDebug() << __PRETTY_FUNCTION__;

    m_dbusInterface = new QDBusInterface("org.maia.WindowManagerX11Service",
                                         "/WindowManagerX11",
                                         "org.maia.WindowManagerX11Interface",
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

    QDBusPendingCall call = m_dbusInterface->asyncCall("reconfigure");
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

    QDBusPendingCall call = m_dbusInterface->asyncCall("unloadEffect", effectName);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &MWindowManagerX11::onCallFinished);
}

void MWindowManagerX11::hideFromTaskbar(const QWindow *window, const bool hide)
{
    //qDebug() << __PRETTY_FUNCTION__;

    if (!window)
        return;

    if (!m_dbusInterface->isValid()) {
        qDebug() << "[ERROR] D-Bus is not available for hideFromTaskbar!";
        return;
    }

    QDBusPendingCall call = m_dbusInterface->asyncCall("hideFromTaskbar", window->winId(), hide);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &MWindowManagerX11::onCallFinished);
}

void MWindowManagerX11::hideFromPager(const QWindow *window, const bool hide)
{
    qDebug() << __PRETTY_FUNCTION__;

    if (!window)
        return;

    if (!m_dbusInterface->isValid()) {
        qDebug() << "D-Bus is not available for hideFromPager!";
        return;
    }

    QDBusPendingCall call = m_dbusInterface->asyncCall("hideFromPager", window->winId(), hide);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &MWindowManagerX11::onCallFinished);
}

void MWindowManagerX11::hideFromSwitcher(const QWindow *window, const bool hide)
{
    qDebug() << __PRETTY_FUNCTION__;

    if (!window)
        return;

    if (!m_dbusInterface->isValid()) {
        qDebug() << "D-Bus is not available for hideFromSwitcher!";
        return;
    }

    QDBusPendingCall call = m_dbusInterface->asyncCall("hideFromSwitcher", window->winId(), hide);
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
