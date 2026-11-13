#include "NotificationRoles.h"

#include <QDateTime>
#include <QVariantMap>

namespace MaiaNotifications::NotificationRoles {

QHash<int, QByteArray> names()
{
    return {
        {NotificationIdRole, "notificationId"},
        {AppNameRole, "appName"},
        {DesktopEntryRole, "desktopEntry"},
        {AppIconRole, "appIcon"},
        {SummaryRole, "summary"},
        {BodyRole, "body"},
        {ImageRole, "image"},
        {ActionsRole, "actions"},
        {HasDefaultActionRole, "hasDefaultAction"},
        {ActionIconsRole, "actionIcons"},
        {UrgencyRole, "urgency"},
        {CategoryRole, "category"},
        {TimeoutRole, "timeout"},
        {TimeRole, "time"},
        {TransientRole, "transient"},
        {ResidentRole, "resident"},
        {PopupRole, "popup"},
        {ExpiredRole, "expired"},
        {InlineReplyRole, "inlineReply"},
        {ReplyPlaceholderRole, "replyPlaceholder"},
        {ReplySubmitTextRole, "replySubmitText"},
        {OriginNameRole, "originName"},
        {UrlsRole, "urls"},
        {SoundNameRole, "soundName"},
        {SoundFileRole, "soundFile"},
        {SuppressSoundRole, "suppressSound"},
    };
}

QVariant data(const NotificationData &n, int role)
{
    switch (role) {
    case NotificationIdRole:
        return n.id;
    case AppNameRole:
        return n.appName;
    case DesktopEntryRole:
        return n.desktopEntry;
    case AppIconRole:
        return n.appIcon;
    case SummaryRole:
        return n.summary;
    case BodyRole:
        return n.body;
    case ImageRole:
        return n.image;
    case ActionsRole: {
        QVariantList list;
        for (const auto &action : n.actions) {
            if (action.key != QLatin1String("default"))
                list.append(QVariantMap{{QStringLiteral("key"), action.key}, {QStringLiteral("label"), action.label}});
        }
        return list;
    }
    case HasDefaultActionRole:
        return n.hasAction(QStringLiteral("default"));
    case ActionIconsRole:
        return n.actionIcons;
    case UrgencyRole:
        return n.urgency;
    case CategoryRole:
        return n.category;
    case TimeoutRole:
        return n.timeout;
    case TimeRole:
        return QDateTime::fromMSecsSinceEpoch(n.time);
    case TransientRole:
        return n.transient;
    case ResidentRole:
        return n.resident;
    case PopupRole:
        return n.popup;
    case ExpiredRole:
        return n.expired;
    case InlineReplyRole:
        return n.inlineReply;
    case ReplyPlaceholderRole:
        return n.replyPlaceholder;
    case ReplySubmitTextRole:
        return n.replySubmitText;
    case OriginNameRole:
        return n.originName;
    case UrlsRole:
        return n.urls;
    case SoundNameRole:
        return n.soundName;
    case SoundFileRole:
        return n.soundFile;
    case SuppressSoundRole:
        return n.suppressSound;
    }
    return {};
}

} // namespace MaiaNotifications::NotificationRoles
