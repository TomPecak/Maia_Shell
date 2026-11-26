#include "Tray.h"

#include "TrayConnection.h"

#include <QFutureWatcher>
#include <QGuiApplication>
#include <QTimer>

#include <KWaylandExtras>

#include <algorithm>
#include <memory>

namespace MaiaTray {

namespace {
// How long a click waits for the compositor's token at most
constexpr int kTokenWait = 300;
}

Tray::Tray(QObject *parent)
    : QObject(parent)
{
    auto *connection = TrayConnection::instance();
    connect(connection, &ServiceLink::connectedChanged, this, &Tray::connectedChanged);
    connect(connection, &TrayConnection::reset, this, &Tray::recount);
    connect(connection, &TrayConnection::batch, this, &Tray::recount);
    recount();
}

bool Tray::connected() const
{
    return TrayConnection::instance()->isConnected();
}

int Tray::count() const
{
    return m_count;
}

void Tray::recount()
{
    const auto &items = TrayConnection::instance()->items();
    const int count = int(items.size());
    const int attention = int(std::count_if(items.cbegin(), items.cend(), [](const ItemData &item) { return item.status == ItemStatus::NeedsAttention; }));
    if (m_count != count) {
        m_count = count;
        Q_EMIT countChanged();
    }
    if (m_attentionCount != attention) {
        m_attentionCount = attention;
        Q_EMIT attentionCountChanged();
    }
}

void Tray::withToken(QWindow *window, const QString &appId, std::function<void(const QString &)> send)
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
    auto *context = QCoreApplication::instance();
    auto *watcher = new QFutureWatcher<QString>(context);
    QObject::connect(watcher, &QFutureWatcherBase::finished, context, [watcher, once] {
        once(watcher->result());
        watcher->deleteLater();
    });
    watcher->setFuture(KWaylandExtras::xdgActivationToken(window, appId));
    QTimer::singleShot(kTokenWait, context, [once] { once(QString()); });
}

void Tray::activate(uint itemId, int x, int y, QWindow *window)
{
    const ItemData *item = TrayConnection::instance()->find(itemId);
    if (!item)
        return;
    withToken(window, item->desktopEntry, [itemId, x, y](const QString &token) { TrayConnection::instance()->activate(itemId, x, y, token); });
}

void Tray::secondaryActivate(uint itemId, int x, int y, QWindow *window)
{
    const ItemData *item = TrayConnection::instance()->find(itemId);
    if (!item)
        return;
    withToken(window, item->desktopEntry, [itemId, x, y](const QString &token) {
        TrayConnection::instance()->secondaryActivate(itemId, x, y, token);
    });
}

void Tray::contextMenu(uint itemId, int x, int y)
{
    TrayConnection::instance()->contextMenu(itemId, x, y);
}

void Tray::scroll(uint itemId, int delta, bool horizontal)
{
    TrayConnection::instance()->scroll(itemId, delta, horizontal);
}

} // namespace MaiaTray
