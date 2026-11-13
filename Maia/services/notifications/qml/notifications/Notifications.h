#pragma once

// Notifications: the state of the notification service for senders, a singleton.
//
//   import Maia.Notifications
//   Label { visible: !Notifications.available; text: qsTr("Notifications are not available") }

#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class Notifications : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // The service runs; notifications sent without it wait for it
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit Notifications(QObject *parent = nullptr);

    bool available() const;

Q_SIGNALS:
    void availableChanged();
};

} // namespace MaiaNotifications
