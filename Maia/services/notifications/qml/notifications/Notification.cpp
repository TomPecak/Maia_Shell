#include "Notification.h"

#include "Contract.h"
#include "NotifierConnection.h"

#include <QGuiApplication>
#include <QVariantMap>
#include <QWindow>

#include <KWindowSystem>

namespace MaiaNotifications {

Notification::Notification(QObject *parent)
    : QObject(parent)
    , m_appName(QGuiApplication::applicationDisplayName())
    , m_desktopEntry(QGuiApplication::desktopFileName())
{
}

void Notification::onSent(uint id)
{
    if (id == m_id)
        return;
    m_id = id;
    Q_EMIT notificationIdChanged();
}

void Notification::onActionInvoked(const QString &key, const QString &token)
{
    m_activationToken = token;
    Q_EMIT actionInvoked(key);
}

void Notification::onReplied(const QString &text, const QString &token)
{
    m_activationToken = token;
    Q_EMIT replied(text);
}

void Notification::onClosed(int reason)
{
    setLocal(0);
    Q_EMIT closed(CloseReason(reason));
}

Notification::~Notification()
{
    if (m_local != 0)
        NotifierConnection::instance()->release(m_local);
}

RequestData Notification::request() const
{
    RequestData r;
    r.appName = m_appName;
    r.desktopEntry = m_desktopEntry;
    r.appIcon = m_iconName;
    r.summary = m_summary;
    r.body = m_body;
    r.image = m_image.isLocalFile() ? m_image.toLocalFile() : QString();
    for (const QVariant &value : m_actions) {
        const QVariantMap action = value.toMap();
        const QString key = action.value(QStringLiteral("key")).toString();
        if (!key.isEmpty())
            r.actions.append({key, action.value(QStringLiteral("label")).toString()});
    }
    r.actionIcons = m_actionIcons;
    r.urgency = int(m_urgency);
    r.category = m_category;
    r.timeout = m_timeout;
    r.transient = m_transient;
    r.resident = m_resident;
    r.inlineReply = m_inlineReply;
    r.replyPlaceholder = m_replyPlaceholder;
    r.replySubmitText = m_replySubmitText;
    r.soundName = m_soundName;
    r.suppressSound = m_suppressSound;
    for (const QUrl &url : m_urls) {
        if (url.isValid())
            r.urls.append(url.isLocalFile() ? url.toLocalFile() : url.toString(QUrl::FullyEncoded));
    }
    return r;
}

void Notification::setLocal(int local)
{
    const bool wasActive = isActive();
    m_local = local;
    if (local == 0 && m_id != 0) {
        m_id = 0;
        Q_EMIT notificationIdChanged();
    }
    if (wasActive != isActive())
        Q_EMIT activeChanged();
}

void Notification::send()
{
    auto *connection = NotifierConnection::instance();
    if (m_local != 0)
        connection->update(m_local, request());
    else
        setLocal(connection->send(request(), this));
}

void Notification::close()
{
    if (m_local != 0)
        NotifierConnection::instance()->close(m_local);
}

void Notification::activate(QWindow *window)
{
    if (!window)
        return;
    if (!m_activationToken.isEmpty())
        KWindowSystem::setCurrentXdgActivationToken(m_activationToken);
    KWindowSystem::activateWindow(window);
}

#define MAIA_SETTER(Type, name, member)                                                                                \
    void Notification::name(Type value)                                                                                \
    {                                                                                                                  \
        if (member == value)                                                                                           \
            return;                                                                                                    \
        member = value;                                                                                                \
        Q_EMIT changed();                                                                                              \
    }

MAIA_SETTER(const QString &, setAppName, m_appName)
MAIA_SETTER(const QString &, setDesktopEntry, m_desktopEntry)
MAIA_SETTER(const QString &, setIconName, m_iconName)
MAIA_SETTER(const QString &, setSummary, m_summary)
MAIA_SETTER(const QString &, setBody, m_body)
MAIA_SETTER(const QUrl &, setImage, m_image)
MAIA_SETTER(const QVariantList &, setActions, m_actions)
MAIA_SETTER(bool, setActionIcons, m_actionIcons)
MAIA_SETTER(Urgency, setUrgency, m_urgency)
MAIA_SETTER(const QString &, setCategory, m_category)
MAIA_SETTER(int, setTimeout, m_timeout)
MAIA_SETTER(bool, setTransient, m_transient)
MAIA_SETTER(bool, setResident, m_resident)
MAIA_SETTER(bool, setInlineReply, m_inlineReply)
MAIA_SETTER(const QString &, setReplyPlaceholder, m_replyPlaceholder)
MAIA_SETTER(const QString &, setReplySubmitText, m_replySubmitText)
MAIA_SETTER(const QString &, setSoundName, m_soundName)
MAIA_SETTER(bool, setSuppressSound, m_suppressSound)
MAIA_SETTER(const QList<QUrl> &, setUrls, m_urls)

#undef MAIA_SETTER

} // namespace MaiaNotifications
