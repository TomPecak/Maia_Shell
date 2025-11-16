#include "processproviderlauncher.h"
#include <QDBusInterface>
#include <QDBusPendingCall>
#include <QProcess>

ProcessProviderLauncher::ProcessProviderLauncher(QObject *parent)
    : QObject(parent)
{

}

bool ProcessProviderLauncher::startDetached(const QString &exec, QStringList args)
{
    // QDBusInterface iface("com.cutefish.Session",
    //                      "/Session",
    //                      "com.cutefish.Session", QDBusConnection::sessionBus());

    // if (iface.isValid()) {
    //     iface.asyncCall("launch", exec, args).waitForFinished();
    //     return true;
    // } else {
        QProcess process;
        process.startDetached(exec, args);
    //}

    return false;
}
