#include "X11WindowManagerService.hpp"

#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QElapsedTimer>

#include <KX11Extras>

WindowManagerX11Service::WindowManagerX11Service(QObject *parent)
    : QObject(parent)
    , m_kwinBus(QDBusConnection::sessionBus())
{
    qDebug() << "[STARTUP INFO] Starting: " << __PRETTY_FUNCTION__;
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

    if (!bus.registerService(QStringLiteral("org.maia.WindowManagerX11Service"))) {
        qDebug() << "[ERROR] Failed to register D-Bus service";
        return;
    }

    if (!bus.registerObject(QStringLiteral("/WindowManagerX11"),
                            this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qDebug() << "[ERROR] Failed to register D-Bus object.";
    }

    QDBusConnection::sessionBus().connect(QStringLiteral("org.kde.KWin"),                // Service name
                                          QStringLiteral("/KWin"),                       // Object path
                                          QStringLiteral("org.kde.KWin"),                // Interface name
                                          QStringLiteral("reloadConfig"),                // Signal name
                                          this,                          // Receiver object
                                          SLOT(handleKwinConfigReloaded) // Slot to be called
                                          );
}

WindowManagerX11Service::~WindowManagerX11Service() {}

void WindowManagerX11Service::unloadEffect(const QString &effectName)
{
    //qDebug() << __PRETTY_FUNCTION__ << " effectName = " << effectName;

    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),         // Service
                                                          QStringLiteral("/Effects"),             // Path
                                                          QStringLiteral("org.kde.kwin.Effects"), // Interface
                                                          QStringLiteral("unloadEffect")          // Method
    );

    message << effectName;

    QDBusPendingCall pendingCall = m_kwinBus.asyncCall(message);

    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pendingCall, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, effectName, watcher]() {
        QDBusPendingReply<> reply = *watcher;
        if (reply.isError()) {
            //Q_EMIT errorOccurred(effectName, reply.error().message());
            qDebug() << "[ERROR] " << __PRETTY_FUNCTION__ << " D-Bus unloadEffect error, effectName=" << effectName
                     << ":" << reply.error().message();
        } else {
            //Q_EMIT effectUnloaded(effectName);
            //qDebug() << "[OK] Successfull unload " << effectName << " effect";
        }
        watcher->deleteLater();
    });
}

void WindowManagerX11Service::reconfigure()
{

    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), // Service
                                                          QStringLiteral("/KWin"),        // Path
                                                          QStringLiteral("org.kde.KWin"), // Interface
                                                          QStringLiteral("reconfigure")   // Method
                                                          );

    // Create and start a timer
    QElapsedTimer timer;
    timer.start();

    QDBusPendingCall pendingCall = m_kwinBus.asyncCall(message);

    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(pendingCall, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [=]() mutable {
        // Measure and display the time elapsed since timer.start()
        qint64 elapsed_ms = timer.elapsed();
        double elapsed_us = timer.nsecsElapsed() / 1000.0; // In microseconds for greater precision

        qDebug() << ">>> Signal 'finished' received after:" << elapsed_ms << "ms (" << elapsed_us
                 << "µs)";

        QDBusPendingReply<> reply = *watcher;
        bool success = !reply.isError();
        if (reply.isError()) {
            qDebug() << "[ERROR] D-Bus error during reconfiguration:" << reply.error().message();
        } else {
            qDebug() << "KWin reconfiguration completed successfully.";
        }
        Q_EMIT reconfigureFinished(success); // Emit signal with success information
        watcher->deleteLater();
    });
}

void WindowManagerX11Service::hideFromTaskbar(WId winId, bool hide)
{
    if (hide)
        KX11Extras::setState(winId, NET::SkipTaskbar);
    else
        KX11Extras::clearState(winId, NET::SkipTaskbar);
}

void WindowManagerX11Service::hideFromPager(WId winId, bool hide)
{
    if (hide)
        KX11Extras::setState(winId, NET::SkipPager);
    else
        KX11Extras::clearState(winId, NET::SkipPager);
}

void WindowManagerX11Service::hideFromSwitcher(WId winId, bool hide)
{
    if (hide)
        KX11Extras::setState(winId, NET::SkipSwitcher);
    else
        KX11Extras::clearState(winId, NET::SkipSwitcher);
}

void WindowManagerX11Service::handleKwinConfigReloaded()
{

}
