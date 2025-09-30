#pragma once

#include <QObject>
#include <QMap>
#include <QVariantList>

#include "FrontendInfo.hpp"

class FrontendManagerService : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.maia.FrontendManager")

public:
    explicit FrontendManagerService(QObject *parent = nullptr);
    ~ FrontendManagerService();

    //internal Server api
    void activeFrontendChangeConfirmation(const QString &frontendId);
    FrontendInfo getCurrentFrontent();

public slots:
    //D-Bus API
    QVariantList getFrontendList();
    QString activeFrontend() const;
    void setActiveFrontend(const QString &frontendId);

signals:
    //D-Bus API
    Q_SCRIPTABLE void frontendAdded(const QString &id,
                                    const QString &name,
                                    const QString &description,
                                    const QString &path);
    Q_SCRIPTABLE void frontendRemoved(const QString &id);
    Q_SCRIPTABLE void activeFrontendChanged(const QString &frontendId);

    //internal Server api
    void activeFrontendChangeRequest(const QString & forntendId);
    void activeFrontendChangeRequest(const FrontendInfo & forntendId);

private:
    QMap<QString, FrontendInfo> m_frontends;
    QString m_activeFrontendId;

    void loadFrontends();
    void addFrontend(const FrontendInfo &frontend);
    void removeFrontend(const QString &frontendId);

    QString readActiveFronted();
    void saveActiveFronted(const QString &frontedId);
};
