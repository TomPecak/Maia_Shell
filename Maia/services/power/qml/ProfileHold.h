#pragma once

// ProfileHold: holds a power profile while it is active (e.g. performance while a game runs, power
// saving during a presentation), declaratively.
//
//   ProfileHold { active: compiling; profile: Power.Performance; reason: qsTr("Compiling") }
//
// The profile the user chose comes back when the last hold ends. The hold also ends when this
// object is destroyed, when its process ends or loses the service; after a reconnection it is
// made again. held tells whether the system holds it now.

#include "PowerConnection.h"
#include "Power.h"

#include <QObject>
#include <QQmlParserStatus>
#include <QtQml/qqmlregistration.h>

namespace MaiaPower {

class ProfileHold : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(MaiaPower::Power::Profile profile READ profile WRITE setProfile NOTIFY profileChanged)
    // Shown to the user ("Compiling"); applicationId defaults to the application's desktop file name
    Q_PROPERTY(QString reason READ reason WRITE setReason NOTIFY reasonChanged)
    Q_PROPERTY(QString applicationId READ applicationId WRITE setApplicationId NOTIFY applicationIdChanged)
    Q_PROPERTY(bool held READ held NOTIFY heldChanged)

public:
    explicit ProfileHold(QObject *parent = nullptr);
    ~ProfileHold() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    Power::Profile profile() const { return m_profile; }
    void setProfile(Power::Profile profile);
    QString reason() const { return m_reason; }
    void setReason(const QString &reason);
    QString applicationId() const;
    void setApplicationId(const QString &applicationId);
    bool held() const { return m_held; }

    void classBegin() override {}
    void componentComplete() override;

Q_SIGNALS:
    void activeChanged();
    void profileChanged();
    void reasonChanged();
    void applicationIdChanged();
    void heldChanged();
    // The service refused (e.g. the profile is not offered on this machine); message is for logs
    void failed(MaiaPower::Power::Error error, const QString &message);

private:
    void update();
    void release();
    void setHeld(bool held);

    PowerConnection *m_connection;
    bool m_complete = false;
    bool m_active = false;
    Power::Profile m_profile = Power::Performance;
    QString m_reason;
    QString m_applicationId;
    int m_holdId = 0;
    bool m_held = false;
};

} // namespace MaiaPower
