#include "LocaleSettingsService.hpp"

#include <KSharedConfig>
#include <KConfigGroup>
#include "../maia_version.h"

LocaleSettingsService::LocaleSettingsService(QObject *parent)
    : QObject(parent)
    , m_twentyFourTime(false)
    , m_isRegistered(false)
{
    // Load settings first to expose correct state on D-Bus immediately
    loadSettings();

    auto connection = QDBusConnection::sessionBus();

    if (!connection.registerService(ServiceName)) {
        qCritical() << "[Service] CRITICAL: Failed to register service:"
                    << ServiceName
                    << connection.lastError().message();
        return;
    }

    bool success = connection.registerObject(ObjectPath,
                                             this,
                                             QDBusConnection::ExportAllProperties |
                                                 QDBusConnection::ExportAllSignals |
                                                 QDBusConnection::ExportAllSlots);

    if (!success) {
        qCritical() << "[Service] CRITICAL: Failed to register object at path:"
                    << ObjectPath;
    } else {
        m_isRegistered = true;
        qDebug() << "[Service] Successfully registered at:" << ServiceName;
    }
}

LocaleSettingsService::~LocaleSettingsService()
{
    if (m_isRegistered) {
        QDBusConnection::sessionBus().unregisterObject(ObjectPath);
        QDBusConnection::sessionBus().unregisterService(ServiceName);
        qDebug() << "[Service] Service unregistered.";
    }
}

bool LocaleSettingsService::twentyFourTime() const
{
    return m_twentyFourTime;
}

void LocaleSettingsService::setTwentyFourTime(bool newTwentyFourTime)
{
    if (m_twentyFourTime == newTwentyFourTime)
        return;

    m_twentyFourTime = newTwentyFourTime;
    qDebug() << "[Service] Value changed to:" << m_twentyFourTime;

    // Persist change to disk
    saveSettings();

    emit twentyFourTimeChanged(m_twentyFourTime);
}

void LocaleSettingsService::loadSettings()
{
    QString configPath = QString("./Maia/maiarc_") + MAIA_VERSION_STRING;

    KSharedConfig::Ptr config = KSharedConfig::openConfig(configPath);
    KConfigGroup group = config->group("LocaleSettingsService");

    // Read with default value (false)
    m_twentyFourTime = group.readEntry("twentyFourTime", false);

    qDebug() << "[Service] Loaded settings: twentyFourTime =" << m_twentyFourTime;
}

void LocaleSettingsService::saveSettings()
{
    QString configPath = QString("./Maia/maiarc_") + MAIA_VERSION_STRING;

    KSharedConfig::Ptr config = KSharedConfig::openConfig(configPath);
    KConfigGroup group = config->group("LocaleSettingsService");

    group.writeEntry("twentyFourTime", m_twentyFourTime);
    config->sync(); // Force save to disk

    qDebug() << "[Service] Saved settings: twentyFourTime =" << m_twentyFourTime;
}
