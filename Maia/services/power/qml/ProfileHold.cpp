#include "ProfileHold.h"

#include <QGuiApplication>

namespace MaiaPower {

ProfileHold::ProfileHold(QObject *parent)
    : QObject(parent)
    , m_connection(PowerConnection::instance())
{
    connect(m_connection, &PowerConnection::connectedChanged, this, [this] {
        // A new connection: the old hold went with the old one
        m_holdId = 0;
        setHeld(false);
        update();
    });
    connect(m_connection, &PowerConnection::holdFinished, this, [this](int id, int error, const QString &message) {
        if (id != m_holdId)
            return;
        if (error == Power::NoError) {
            setHeld(true);
        } else {
            m_holdId = 0;
            setHeld(false);
            Q_EMIT failed(Power::Error(error), message);
        }
    });
}

ProfileHold::~ProfileHold()
{
    release();
}

QString ProfileHold::applicationId() const
{
    if (!m_applicationId.isEmpty())
        return m_applicationId;
    const QString desktop = QGuiApplication::desktopFileName();
    return desktop.isEmpty() ? QCoreApplication::applicationName() : desktop;
}

void ProfileHold::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    Q_EMIT activeChanged();
    update();
}

void ProfileHold::setProfile(Power::Profile profile)
{
    if (m_profile == profile)
        return;
    m_profile = profile;
    Q_EMIT profileChanged();
    // A held hold changes profile: a new one
    release();
    update();
}

void ProfileHold::setReason(const QString &reason)
{
    if (m_reason == reason)
        return;
    m_reason = reason;
    Q_EMIT reasonChanged();
}

void ProfileHold::setApplicationId(const QString &applicationId)
{
    if (m_applicationId == applicationId)
        return;
    m_applicationId = applicationId;
    Q_EMIT applicationIdChanged();
}

void ProfileHold::componentComplete()
{
    m_complete = true;
    update();
}

void ProfileHold::update()
{
    if (!m_complete)
        return;
    if (!m_active) {
        release();
        return;
    }
    if (m_holdId == 0 && m_connection->isConnected())
        m_holdId = m_connection->holdProfile(int(m_profile), m_reason, applicationId());
}

void ProfileHold::release()
{
    if (m_holdId != 0) {
        m_connection->releaseProfile(m_holdId);
        m_holdId = 0;
    }
    setHeld(false);
}

void ProfileHold::setHeld(bool held)
{
    if (m_held == held)
        return;
    m_held = held;
    Q_EMIT heldChanged();
}

} // namespace MaiaPower
