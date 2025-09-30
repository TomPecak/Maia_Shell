#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QWindow>

class WindowManagerX11Service : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.maia.WindowManagerX11Interface")
public:
    explicit WindowManagerX11Service(QObject *parent = nullptr);
    ~WindowManagerX11Service();

signals:
    // void effectUnloaded(const QString &effectName);
    // void errorOccurred(const QString &effectName, const QString &errorMessage);
    void reconfigureFinished(bool success); // Nowy sygnał

public slots:
    void unloadEffect(const QString &effectName);
    void reconfigure();
    void hideFromTaskbar(WId winId, bool hide);
    void hideFromPager(WId winId, bool hide);
    void hideFromSwitcher(WId winId, bool hide);

private slots:
    void handleKwinConfigReloaded();

private:
    QDBusConnection m_kwinBus;
};
