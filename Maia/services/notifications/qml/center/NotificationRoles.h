#pragma once

// The roles of a notification, shared by NotificationsModel and NotificationPopupsModel.
//
//   notificationId, appName, desktopEntry, appIcon (a theme icon name or a file URL), summary (plain
//   text), body (StyledText: <b> <i> <u> <a> <br/>), image (a file URL, "" none), actions
//   ([{ key, label }] without "default"), hasDefaultAction (a click on the notification does
//   something), actionIcons, urgency (NotificationCenter.Urgency), category, timeout (ms, -1, 0),
//   time (a date), transient, resident, popup, expired, inlineReply, replyPlaceholder,
//   replySubmitText, originName, urls, soundName, soundFile, suppressSound

#include "NotificationData.h"

#include <QHash>
#include <QVariant>

namespace MaiaNotifications {

namespace NotificationRoles {

enum Role {
    NotificationIdRole = Qt::UserRole + 1,
    AppNameRole,
    DesktopEntryRole,
    AppIconRole,
    SummaryRole,
    BodyRole,
    ImageRole,
    ActionsRole,
    HasDefaultActionRole,
    ActionIconsRole,
    UrgencyRole,
    CategoryRole,
    TimeoutRole,
    TimeRole,
    TransientRole,
    ResidentRole,
    PopupRole,
    ExpiredRole,
    InlineReplyRole,
    ReplyPlaceholderRole,
    ReplySubmitTextRole,
    OriginNameRole,
    UrlsRole,
    SoundNameRole,
    SoundFileRole,
    SuppressSoundRole,
};

QHash<int, QByteArray> names();
QVariant data(const NotificationData &n, int role);

} // namespace NotificationRoles

} // namespace MaiaNotifications
