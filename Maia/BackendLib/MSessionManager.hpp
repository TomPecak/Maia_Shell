#pragma once

#include <QObject>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <qqml.h>

class MSessionManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    MSessionManager(QObject *parent = nullptr);
    ~MSessionManager();

    Q_INVOKABLE void logout();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void poweroff();

private:
    QDBusInterface *m_dbusInterface;

private Q_SLOTS:
    void onCallFinished(QDBusPendingCallWatcher *watcher);
};
