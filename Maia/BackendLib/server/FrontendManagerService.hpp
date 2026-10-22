#pragma once

#include <QObject>
#include <QMap>
#include <QVariantMap>

#include "FrontendInfo.hpp"

// D-Bus service org.maia.FrontendManager. The contract is dbus/org.maia.FrontendManager.xml; the object is
// exported through the adaptor generated from it, so only what the contract lists is visible on the bus.
class FrontendManagerService : public QObject {
    Q_OBJECT

public:
    explicit FrontendManagerService(QObject *parent = nullptr);
    ~ FrontendManagerService();

    //internal Server api
    void activeFrontendChangeConfirmation(const QString &frontendId);
    FrontendInfo getCurrentFrontent();

public Q_SLOTS:
    //D-Bus API
    QList<QVariantMap> getFrontendList();
    QString activeFrontend() const;
    void setActiveFrontend(const QString &frontendId);

Q_SIGNALS:
    //D-Bus API
    void frontendAdded(const QVariantMap &frontend);
    void frontendRemoved(const QString &frontendId);
    void activeFrontendChanged(const QString &frontendId);

    //internal Server api
    void activeFrontendChangeRequest(const QString & forntendId);
    void activeFrontendChangeRequest(const FrontendInfo & forntendId);

private:
    QMap<QString, FrontendInfo> m_frontends;
    QString m_activeFrontendId;

    void loadFrontends();
    QVariantMap frontendMap(const FrontendInfo &frontend) const;
    void addFrontend(const FrontendInfo &frontend);
    void removeFrontend(const QString &frontendId);

    QString readActiveFronted();
    void saveActiveFronted(const QString &frontedId);
};
