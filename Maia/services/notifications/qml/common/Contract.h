#pragma once

// The values of the contract (../../contract/notifications.capnp) translated from and to the plain
// Qt values of NotificationData.h. Readers run in the KJ thread, so that the GUI thread gets
// finished QStrings.

#include "NotificationData.h"

#include "notifications.capnp.h"

namespace MaiaNotifications {

namespace C = Contract;

QString toQString(capnp::Text::Reader text);
NotificationData readNotification(C::Notification::Reader n);
DoNotDisturbData readDoNotDisturb(C::DoNotDisturb::Reader d);
void writeRequest(C::NotificationRequest::Builder b, const RequestData &request);

} // namespace MaiaNotifications
