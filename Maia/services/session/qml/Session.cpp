#include "Session.h"

#include <QDebug>

namespace MaiaSession {

namespace {

QString actionName(Action action)
{
    switch (action) {
    case Action::Logout:
        return QStringLiteral("logout");
    case Action::Reboot:
        return QStringLiteral("reboot");
    case Action::PowerOff:
        return QStringLiteral("powerOff");
    case Action::Suspend:
        return QStringLiteral("suspend");
    case Action::Hibernate:
        return QStringLiteral("hibernate");
    case Action::HybridSleep:
        return QStringLiteral("hybridSleep");
    case Action::SuspendThenHibernate:
        return QStringLiteral("suspendThenHibernate");
    }
    return QString();
}

Session::Error toError(Error error)
{
    switch (error) {
    case Error::None:
        return Session::NoError;
    case Error::NotAllowed:
        return Session::NotAllowed;
    case Error::NotSupported:
        return Session::NotSupported;
    case Error::Busy:
        return Session::Busy;
    case Error::NotFound:
        return Session::NotFound;
    case Error::Failed:
        break;
    }
    return Session::Failed;
}

} // namespace

Session::Session(QObject *parent)
    : QObject(parent)
    , m_connection(SessionConnection::instance())
{
    connect(m_connection, &SessionConnection::connectedChanged, this, &Session::connectedChanged);
    connect(m_connection, &SessionConnection::stateChanged, this, &Session::stateChanged);
    connect(m_connection, &SessionConnection::capabilitiesChanged, this, &Session::capabilitiesChanged);
    connect(m_connection, &SessionConnection::actionFinished, this,
            [this](Action action, MaiaSession::Error error, const QString &message) {
        if (error == MaiaSession::Error::None)
            return;
        qWarning() << "[Maia.Session]" << actionName(action) << "did not happen:" << message;
        Q_EMIT actionFailed(actionName(action), toError(error), message);
    });
}

bool Session::connected() const
{
    return m_connection->isConnected();
}

Session::State Session::state() const
{
    switch (m_connection->state()) {
    case MaiaSession::State::Starting:
        return Starting;
    case MaiaSession::State::Running:
        return Running;
    case MaiaSession::State::Ending:
        return Ending;
    case MaiaSession::State::Sleeping:
        return Sleeping;
    }
    return Starting;
}

Session::EndAction Session::endingAction() const
{
    switch (m_connection->endingAction()) {
    case MaiaSession::EndAction::Logout:
        return Logout;
    case MaiaSession::EndAction::Reboot:
        return Reboot;
    case MaiaSession::EndAction::PowerOff:
        return PowerOff;
    }
    return Logout;
}

bool Session::endingByUser() const
{
    return m_connection->endingByUser();
}

bool Session::canLogout() const
{
    return m_connection->capabilities().logout;
}

bool Session::canPowerOff() const
{
    return m_connection->capabilities().powerOff != Ability::No;
}

bool Session::canReboot() const
{
    return m_connection->capabilities().reboot != Ability::No;
}

bool Session::canSuspend() const
{
    return m_connection->capabilities().suspend != Ability::No;
}

bool Session::canHibernate() const
{
    return m_connection->capabilities().hibernate != Ability::No;
}

bool Session::canHybridSleep() const
{
    return m_connection->capabilities().hybridSleep != Ability::No;
}

bool Session::canSuspendThenHibernate() const
{
    return m_connection->capabilities().suspendThenHibernate != Ability::No;
}

bool Session::powerOffNeedsAuthorization() const
{
    return m_connection->capabilities().powerOff == Ability::Challenge;
}

bool Session::rebootNeedsAuthorization() const
{
    return m_connection->capabilities().reboot == Ability::Challenge;
}

void Session::logout()
{
    m_connection->request(Action::Logout);
}

void Session::reboot()
{
    m_connection->request(Action::Reboot);
}

void Session::powerOff()
{
    m_connection->request(Action::PowerOff);
}

void Session::suspend()
{
    m_connection->request(Action::Suspend);
}

void Session::hibernate()
{
    m_connection->request(Action::Hibernate);
}

void Session::hybridSleep()
{
    m_connection->request(Action::HybridSleep);
}

void Session::suspendThenHibernate()
{
    m_connection->request(Action::SuspendThenHibernate);
}

} // namespace MaiaSession
