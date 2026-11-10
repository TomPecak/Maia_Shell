#pragma once

// Session: the Maia session for QML, a singleton (one per QML engine, sharing the process's
// SessionConnection).
//
//   import Maia.Session
//
//   Button { visible: Session.canPowerOff; onClicked: Session.powerOff() }
//   Text { visible: Session.state === Session.Ending; text: qsTr("Signing out…") }
//
// What the system offers comes from systemd-logind through the session service; can* is true also
// when the action needs the administrator's password (*NeedsAuthorization). The actions answer
// through actionFailed when they did not happen (refused, cancelled password, no service); success
// shows itself (the session ends, the machine sleeps).

#include "SessionConnection.h"

#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace MaiaSession {

class Session : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(EndAction endingAction READ endingAction NOTIFY stateChanged)
    // The ending was asked for in the shell (not a shutdown from outside, not a crash)
    Q_PROPERTY(bool endingByUser READ endingByUser NOTIFY stateChanged)

    Q_PROPERTY(bool canLogout READ canLogout NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPowerOff READ canPowerOff NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canReboot READ canReboot NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSuspend READ canSuspend NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canHibernate READ canHibernate NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canHybridSleep READ canHybridSleep NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSuspendThenHibernate READ canSuspendThenHibernate NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool powerOffNeedsAuthorization READ powerOffNeedsAuthorization NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool rebootNeedsAuthorization READ rebootNeedsAuthorization NOTIFY capabilitiesChanged)

public:
    enum State { Starting, Running, Ending, Sleeping };
    Q_ENUM(State)
    enum EndAction { Logout, Reboot, PowerOff };
    Q_ENUM(EndAction)
    enum Error { NoError, NotAllowed, NotSupported, Busy, NotFound, Failed };
    Q_ENUM(Error)

    explicit Session(QObject *parent = nullptr);

    bool connected() const;
    State state() const;
    EndAction endingAction() const;
    bool endingByUser() const;

    bool canLogout() const;
    bool canPowerOff() const;
    bool canReboot() const;
    bool canSuspend() const;
    bool canHibernate() const;
    bool canHybridSleep() const;
    bool canSuspendThenHibernate() const;
    bool powerOffNeedsAuthorization() const;
    bool rebootNeedsAuthorization() const;

    Q_INVOKABLE void logout();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void powerOff();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void hybridSleep();
    Q_INVOKABLE void suspendThenHibernate();

Q_SIGNALS:
    void connectedChanged();
    void stateChanged();
    void capabilitiesChanged();
    // action: "logout", "reboot", "powerOff", "suspend", "hibernate", "hybridSleep", "suspendThenHibernate";
    // message is for logs
    void actionFailed(const QString &action, MaiaSession::Session::Error error, const QString &message);

private:
    SessionConnection *m_connection;
};

} // namespace MaiaSession
