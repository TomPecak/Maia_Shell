#pragma once

#include <QObject>
#include <qqml.h>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusServiceWatcher>
#include <QDBusPendingCallWatcher>

class MLocaleSettings : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool twentyFourTime READ twentyFourTime WRITE setTwentyFourTime NOTIFY twentyFourTimeChanged)

public:
    explicit MLocaleSettings(QObject *parent = nullptr);

    bool twentyFourTime() const;
    void setTwentyFourTime(bool newTwentyFourTime);

signals:
    void twentyFourTimeChanged();

private slots:
    // Slot called when D-Bus sends a signal (Server -> Client)
    void onRemoteChanged(bool value);

    // Service lifecycle handlers
    void onServiceRegistered(const QString &service);
    void onServiceUnregistered(const QString &service);

private:
    // Helper to asynchronously fetch state from server
    void syncWithServer();

    bool m_twentyFourTime;
    QDBusInterface *m_dbusInterface;
    QDBusServiceWatcher *m_watcher;

    // Constants
    const QString ServiceName = QStringLiteral("com.maia.LocaleSettings");
    const QString ObjectPath  = QStringLiteral("/LocaleSettings");
    const QString Interface   = QStringLiteral("com.maia.LocaleSettings");
    const QString PropertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");
};
