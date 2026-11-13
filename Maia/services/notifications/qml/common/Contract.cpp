#include "Contract.h"

namespace MaiaNotifications {

bool NotificationData::hasAction(const QString &key) const
{
    for (const auto &action : actions) {
        if (action.key == key)
            return true;
    }
    return false;
}

QString toQString(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

NotificationData readNotification(C::Notification::Reader n)
{
    NotificationData d;
    d.id = n.getId();
    d.appName = toQString(n.getAppName());
    d.desktopEntry = toQString(n.getDesktopEntry());
    d.appIcon = toQString(n.getAppIcon());
    d.summary = toQString(n.getSummary());
    d.body = toQString(n.getBody());
    d.image = toQString(n.getImage());
    for (auto action : n.getActions())
        d.actions.append({toQString(action.getKey()), toQString(action.getLabel())});
    d.actionIcons = n.getActionIcons();
    d.urgency = int(n.getUrgency());
    d.category = toQString(n.getCategory());
    d.timeout = n.getTimeout();
    d.time = n.getTime();
    d.transient = n.getTransient();
    d.resident = n.getResident();
    d.popup = n.getPopup();
    d.expired = n.getExpired();
    d.inlineReply = n.getInlineReply();
    d.replyPlaceholder = toQString(n.getReplyPlaceholder());
    d.replySubmitText = toQString(n.getReplySubmitText());
    d.originName = toQString(n.getOriginName());
    for (auto url : n.getUrls())
        d.urls.append(toQString(url));
    d.soundName = toQString(n.getSoundName());
    d.soundFile = toQString(n.getSoundFile());
    d.suppressSound = n.getSuppressSound();
    return d;
}

DoNotDisturbData readDoNotDisturb(C::DoNotDisturb::Reader r)
{
    DoNotDisturbData d;
    d.enabled = r.getEnabled();
    d.until = r.getUntil();
    d.active = r.getActive();
    for (auto inhibitor : r.getInhibitors())
        d.inhibitors.append({toQString(inhibitor.getDesktopEntry()), toQString(inhibitor.getAppName()), toQString(inhibitor.getReason())});
    return d;
}

void writeRequest(C::NotificationRequest::Builder b, const RequestData &r)
{
    b.setAppName(r.appName.toUtf8().constData());
    b.setDesktopEntry(r.desktopEntry.toUtf8().constData());
    b.setAppIcon(r.appIcon.toUtf8().constData());
    b.setSummary(r.summary.toUtf8().constData());
    b.setBody(r.body.toUtf8().constData());
    b.setImage(r.image.toUtf8().constData());
    auto actions = b.initActions(uint(r.actions.size()));
    for (int i = 0; i < r.actions.size(); ++i) {
        actions[uint(i)].setKey(r.actions[i].key.toUtf8().constData());
        actions[uint(i)].setLabel(r.actions[i].label.toUtf8().constData());
    }
    b.setActionIcons(r.actionIcons);
    b.setUrgency(C::Urgency(r.urgency));
    b.setCategory(r.category.toUtf8().constData());
    b.setTimeout(r.timeout);
    b.setTransient(r.transient);
    b.setResident(r.resident);
    b.setInlineReply(r.inlineReply);
    b.setReplyPlaceholder(r.replyPlaceholder.toUtf8().constData());
    b.setReplySubmitText(r.replySubmitText.toUtf8().constData());
    b.setSoundName(r.soundName.toUtf8().constData());
    b.setSuppressSound(r.suppressSound);
}

} // namespace MaiaNotifications
