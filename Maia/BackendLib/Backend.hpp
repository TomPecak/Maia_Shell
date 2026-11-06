#pragma once

#include <QObject>
#include <qqml.h>
#include <QCoreApplication>
#include <QDBusMessage>
#include <QDBusConnection>
#include <QTimer>
#include <QFile>
#include <QtGui/qwindowdefs.h>
#include <QQuickWindow>
#include <QProcess>

#include "./private/Mask.hpp"

class Backend : public QObject {
    Q_OBJECT
    QML_ELEMENT
public:
    explicit Backend(QString homeEnv, QObject *parent = nullptr);
    ~Backend();

    //cpu load
    Q_PROPERTY(float cpuLoad READ cpuLoad NOTIFY cpuLoadChanged)
    //turn on cpu load measure
    Q_PROPERTY(bool measureCpuLoad READ measureCpuLoad WRITE setMeasureCpuLoad NOTIFY measureCpuLoadChanged)

    //platform info
    Q_PROPERTY(QString platformName READ platformName NOTIFY platformNameChanged)

    //qt version
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)

    Q_INVOKABLE void installIconTheme(const QUrl &themeUrl, bool forceReinstall = false);
    Q_INVOKABLE void setIconTheme(const QString themeName); // Added for icon theme application

    //mask
    Q_INVOKABLE void addMaskedItem(QQuickItem *item);
    Q_INVOKABLE void removeMaskedItem(QQuickItem *item);

    //window management

    //process
    Q_INVOKABLE void startApplication(const QString &id);
    Q_INVOKABLE void startProcess(const QString &proc);
    Q_INVOKABLE void runCommand(const QString &cmd);

    //panel location


    //platform info
    QString platformName() const;

    //qt version
    QString qtVersion() const;

    //cpu load
    float cpuLoad() const;

    //measure cpu load flag
    bool measureCpuLoad() const;
    void setMeasureCpuLoad(bool enable);

private Q_SLOTS:
    void updateCpuLoad();

Q_SIGNALS:
    void platformNameChanged();
    void cpuLoadChanged();
    void measureCpuLoadChanged();
    void themeReinstallationFailed(const QString &themeName); // Added for error notification

private:
    bool installDirInternal(const QUrl &themeUrl, const QString &targetInstallDirPath, bool forceReinstall);
    bool copyLocalDirectory(const QString &sourcePath, const QString &targetPath);
    bool copyQrcDirectory(const QString &sourcePath, const QString &targetPath);
    bool isUrlInstalled(const QString &themeName, const QUrl &themeUrl);
    void saveInstalledUrl(const QString &themeName, const QUrl &themeUrl);
    void clearInstalledUrl(const QString &themeName);

private:
    QString HOME_ENV;
    QString m_platformName;
    Mask mask;

    //cpu load variables
    float m_cpuLoad = 0.0f;
    QTimer m_timer;
    long long prevTotal = 0;
    long long prevIdle = 0;

    // File for reading CPU load
    QFile m_cpuFile;

    // Flag to control CPU load measurement
    bool m_measureCpuLoad = false;
};
