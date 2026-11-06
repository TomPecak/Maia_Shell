#pragma once

#include <QDBusInterface>
#include <QObject>
#include <qqml.h>

#include <QWindow>

class MWindowManagerX11 : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    MWindowManagerX11(QObject *parent = nullptr);
    ~MWindowManagerX11();

    Q_INVOKABLE void reconfigure();
    Q_INVOKABLE void unloadEffect(const QString &effectName);

private Q_SLOTS:
    void onCallFinished(QDBusPendingCallWatcher *watcher);

private:
    QDBusInterface *m_dbusInterface;
};
