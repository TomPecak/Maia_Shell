#pragma once

#include <QObject>

// The session actions of Maia: log out, suspend, restart, shut down. Registered on the session bus
// as org.maia.SessionService, object /Session, interface org.maia.SessionInterface; frontends call
// it through MSessionManager. Logging out ends Maia (Server::sessionLogout), the power actions go to
// systemd-logind on the system bus.
//
// In a nested development session (MAIA_NESTED_SESSION=1, set by run_maia_nested_wayland.sh) the
// power actions are only logged: logind would suspend, restart or shut down the real machine.
class SessionService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.maia.SessionInterface")
public:
    explicit SessionService(QObject *parent = nullptr);
    ~SessionService();

    //these slots are automaticly exposed by Qt mechanics as d-bus slots
public Q_SLOTS:
    void logout();
    void suspend();
    void reboot();
    void poweroff();

private:
    // org.freedesktop.login1.Manager.<method>(interactive = true): logind asks for a password
    // (polkit) itself when the action needs one
    void callLogind(const QString &method);

    const bool m_nestedSession;

Q_SIGNALS:
    void logoutRequest();
    void suspendRequest();
    void rebootRequest();
    void poweroffRequest();
};
