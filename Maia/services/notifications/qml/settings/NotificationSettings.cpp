#include "NotificationSettings.h"

#include "SettingsConnection.h"

#include <QVariantMap>

namespace MaiaNotifications {

NotificationSettings::NotificationSettings(QObject *parent)
    : QObject(parent)
{
    auto *connection = SettingsConnection::instance();
    connect(connection, &ServiceLink::connectedChanged, this, &NotificationSettings::connectedChanged);
    connect(connection, &SettingsConnection::settingsChanged, this, &NotificationSettings::settingsChanged);
}

bool NotificationSettings::connected() const
{
    return SettingsConnection::instance()->isConnected();
}

bool NotificationSettings::doNotDisturb() const
{
    return SettingsConnection::instance()->settings().doNotDisturb.enabled;
}

void NotificationSettings::setDoNotDisturb(bool enabled)
{
    SettingsConnection::instance()->setDoNotDisturb(enabled, 0);
}

void NotificationSettings::setDoNotDisturbFor(int minutes)
{
    const qint64 until = QDateTime::currentMSecsSinceEpoch() + qint64(qMax(1, minutes)) * 60 * 1000;
    SettingsConnection::instance()->setDoNotDisturb(true, until);
}

QDateTime NotificationSettings::doNotDisturbUntil() const
{
    const qint64 until = SettingsConnection::instance()->settings().doNotDisturb.until;
    return until > 0 ? QDateTime::fromMSecsSinceEpoch(until) : QDateTime();
}

QVariantList NotificationSettings::inhibitors() const
{
    QVariantList list;
    for (const auto &inhibitor : SettingsConnection::instance()->settings().doNotDisturb.inhibitors) {
        list.append(QVariantMap{{QStringLiteral("desktopEntry"), inhibitor.desktopEntry},
                                {QStringLiteral("appName"), inhibitor.appName},
                                {QStringLiteral("reason"), inhibitor.reason}});
    }
    return list;
}

bool NotificationSettings::lockScreenNotifications() const
{
    return SettingsConnection::instance()->settings().shell.lockScreenNotifications;
}

void NotificationSettings::setLockScreenNotifications(bool enabled)
{
    SettingsConnection::instance()->setLockScreenNotifications(enabled);
}

void NotificationSettings::setAppEnabled(const QString &key, bool enabled)
{
    SettingsConnection::instance()->setAppEnabled(key, enabled);
}

} // namespace MaiaNotifications
