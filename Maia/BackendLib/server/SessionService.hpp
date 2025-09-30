#pragma once

#include <QObject>
#include <QDBusPendingCallWatcher>

class SessionService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.maia.SessionInterface")
public:
    explicit SessionService(QObject *parent = nullptr);
    ~SessionService();

    //these slots are automaticly exposed by Qt mechanics as d-bus slots
public slots:
    void logout();
    void reboot();
    void poweroff();

private slots:
    void onCallFinished(QDBusPendingCallWatcher *watcher);

private:
    void executeFreedesktopReboot();
    void executeFreedesktopPoweroff();

signals:
    void logoutRequest();
    void rebootRequest();
    void poweroffRequest();
};
