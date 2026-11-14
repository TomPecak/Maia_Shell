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
JobData readJob(C::Job::Reader j);
void writeRequest(C::NotificationRequest::Builder b, const RequestData &request);
void writeJobProgress(C::JobProgress::Builder b, const JobProgressData &progress);
void writeJobRequest(C::JobRequest::Builder b, const JobRequestData &request);

} // namespace MaiaNotifications
