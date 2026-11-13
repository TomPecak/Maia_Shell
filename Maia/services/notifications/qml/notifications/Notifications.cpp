#include "Notifications.h"

#include "NotifierConnection.h"

namespace MaiaNotifications {

Notifications::Notifications(QObject *parent)
    : QObject(parent)
{
    connect(NotifierConnection::instance(), &ServiceLink::connectedChanged, this, &Notifications::availableChanged);
}

bool Notifications::available() const
{
    return NotifierConnection::instance()->isConnected();
}

} // namespace MaiaNotifications
