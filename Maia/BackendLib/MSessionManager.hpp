#pragma once

#include <QObject>
#include <qqml.h>

// Session actions for the frontends (QML singleton MSessionManager in Maia.Backend):
// log out, suspend, restart, shut down. The actions go to the Maia server (SessionService on the
// session bus), which carries them out; the can* properties tell which power actions the system
// offers (systemd-logind), so a frontend can hide the others.
class MSessionManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Whether logind allows the action in this session (also when it asks for a password first).
    // True until logind answered, and when it cannot be asked.
    Q_PROPERTY(bool canSuspend READ canSuspend NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canReboot READ canReboot NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPowerOff READ canPowerOff NOTIFY capabilitiesChanged)

public:
    MSessionManager(QObject *parent = nullptr);

    Q_INVOKABLE void logout();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void poweroff();

    bool canSuspend() const { return m_canSuspend; }
    bool canReboot() const { return m_canReboot; }
    bool canPowerOff() const { return m_canPowerOff; }

Q_SIGNALS:
    void capabilitiesChanged();

private:
    // A method of org.maia.SessionService, without waiting for it
    void callSessionService(const QString &method);
    // Asks logind (Can<method>) and stores the answer in `flag`
    void queryLogind(const QString &method, bool MSessionManager::*flag);

    bool m_canSuspend = true;
    bool m_canReboot = true;
    bool m_canPowerOff = true;
};
