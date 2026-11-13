#include "NotificationCenter.h"

#include "CenterConnection.h"

#include <QFutureWatcher>
#include <QGuiApplication>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>
#include <QWindow>

#include <KWaylandExtras>

#include <memory>

namespace MaiaNotifications {

NotificationCenter::NotificationCenter(QObject *parent)
    : QObject(parent)
{
    auto *connection = CenterConnection::instance();
    connect(connection, &ServiceLink::connectedChanged, this, &NotificationCenter::connectedChanged);
    connect(connection, &CenterConnection::reset, this, &NotificationCenter::countChanged);
    connect(connection, &CenterConnection::batch, this, [this](const QList<NotificationData> &, const QList<quint32> &) {
        Q_EMIT countChanged();
    });
    connect(connection, &CenterConnection::doNotDisturbChanged, this, &NotificationCenter::doNotDisturbChanged);
}

bool NotificationCenter::connected() const
{
    return CenterConnection::instance()->isConnected();
}

int NotificationCenter::count() const
{
    return int(CenterConnection::instance()->notifications().size());
}

bool NotificationCenter::doNotDisturb() const
{
    return CenterConnection::instance()->doNotDisturb().enabled;
}

void NotificationCenter::setDoNotDisturb(bool enabled)
{
    CenterConnection::instance()->setDoNotDisturb(enabled, 0);
}

void NotificationCenter::setDoNotDisturbFor(int minutes)
{
    const qint64 until = QDateTime::currentMSecsSinceEpoch() + qint64(std::max(1, minutes)) * 60 * 1000;
    CenterConnection::instance()->setDoNotDisturb(true, until);
}

QDateTime NotificationCenter::doNotDisturbUntil() const
{
    const qint64 until = CenterConnection::instance()->doNotDisturb().until;
    return until > 0 ? QDateTime::fromMSecsSinceEpoch(until) : QDateTime();
}

bool NotificationCenter::doNotDisturbActive() const
{
    return CenterConnection::instance()->doNotDisturb().active;
}

QVariantList NotificationCenter::inhibitors() const
{
    QVariantList list;
    for (const auto &inhibitor : CenterConnection::instance()->doNotDisturb().inhibitors) {
        list.append(QVariantMap{
            {QStringLiteral("desktopEntry"), inhibitor.desktopEntry},
            {QStringLiteral("appName"), inhibitor.appName},
            {QStringLiteral("reason"), inhibitor.reason},
        });
    }
    return list;
}

void NotificationCenter::withToken(QWindow *window, const QString &appId, std::function<void(const QString &)> send)
{
    if (!window || QGuiApplication::platformName() != QLatin1String("wayland")) {
        send(QString());
        return;
    }
    // Once: with the token, or without it when the compositor does not answer in time
    auto sent = std::make_shared<bool>(false);
    auto once = [sent, send](const QString &token) {
        if (*sent)
            return;
        *sent = true;
        send(token);
    };
    auto *watcher = new QFutureWatcher<QString>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [watcher, once] {
        once(watcher->result());
        watcher->deleteLater();
    });
    watcher->setFuture(KWaylandExtras::xdgActivationToken(window, appId));
    QTimer::singleShot(kTokenWait, this, [once] { once(QString()); });
}

void NotificationCenter::invokeAction(uint notificationId, const QString &key, QWindow *window)
{
    const NotificationData *n = CenterConnection::instance()->find(notificationId);
    if (!n || !n->hasAction(key))
        return;
    withToken(window, n->desktopEntry, [notificationId, key](const QString &token) {
        CenterConnection::instance()->invokeAction(notificationId, key, token);
    });
}

void NotificationCenter::reply(uint notificationId, const QString &text, QWindow *window)
{
    const NotificationData *n = CenterConnection::instance()->find(notificationId);
    if (!n || !n->inlineReply)
        return;
    withToken(window, n->desktopEntry, [notificationId, text](const QString &token) {
        CenterConnection::instance()->reply(notificationId, text, token);
    });
}

void NotificationCenter::dismiss(uint notificationId)
{
    CenterConnection::instance()->dismiss(notificationId);
}

void NotificationCenter::dismissAll()
{
    CenterConnection::instance()->dismissAll();
}

} // namespace MaiaNotifications
