#include "TrayConnection.h"

#include <QCoreApplication>
#include <QDebug>

namespace MaiaTray {

namespace C = Contract;

namespace {

TrayConnection *s_instance = nullptr;

QString toQString(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.cStr(), int(text.size()));
}

IconData readIcon(C::Icon::Reader i)
{
    return {toQString(i.getName()), toQString(i.getUrl())};
}

ItemData readItem(C::Item::Reader i)
{
    ItemData item;
    item.id = i.getId();
    item.key = toQString(i.getKey());
    item.title = toQString(i.getTitle());
    item.status = ItemStatus(int(i.getStatus()));
    item.category = ItemCategory(int(i.getCategory()));
    item.icon = readIcon(i.getIcon());
    item.attentionIcon = readIcon(i.getAttentionIcon());
    item.overlayIcon = readIcon(i.getOverlayIcon());
    auto tip = i.getToolTip();
    item.toolTipTitle = toQString(tip.getTitle());
    item.toolTipText = toQString(tip.getText());
    item.toolTipIcon = readIcon(tip.getIcon());
    item.hasMenu = i.getHasMenu();
    item.itemIsMenu = i.getItemIsMenu();
    item.desktopEntry = toQString(i.getDesktopEntry());
    item.appName = toQString(i.getAppName());
    item.appIcon = toQString(i.getAppIcon());
    return item;
}

MenuEntries readEntries(capnp::List<C::MenuEntry>::Reader list)
{
    MenuEntries entries;
    entries.reserve(list.size());
    for (auto e : list) {
        MenuEntryData entry;
        entry.id = e.getId();
        entry.separator = e.getSeparator();
        entry.label = toQString(e.getLabel());
        entry.enabled = e.getEnabled();
        entry.icon = readIcon(e.getIcon());
        entry.toggle = int(e.getToggle());
        entry.checked = e.getChecked();
        entry.shortcut = toQString(e.getShortcut());
        entry.submenu = e.getSubmenu();
        entry.children = readEntries(e.getChildren());
        entries.push_back(std::move(entry));
    }
    return entries;
}

// Logs a refused request: the shell has nothing to show for it (the item was gone)
template<typename Response>
void logResult(const char *action, Response &&response)
{
    auto result = response.getResult();
    if (result.getError() != C::ErrorCode::NONE)
        qDebug() << "[Maia.Tray]" << action << "refused:" << toQString(result.getMessage());
}

} // namespace

// The service's calls (KJ thread): read into Qt values here, applied in the GUI thread
class ShellListener final : public C::TrayListener::Server
{
public:
    explicit ShellListener(TrayConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        QList<ItemData> list;
        auto items = context.getParams().getItems();
        list.reserve(items.size());
        for (auto i : items)
            list.append(readItem(i));
        m_connection->toGui([c = m_connection, list = std::move(list)] { c->applySnapshot(list); });
        return kj::READY_NOW;
    }

    kj::Promise<void> changes(ChangesContext context) override
    {
        auto p = context.getParams();
        QList<ItemData> changed;
        changed.reserve(p.getChanged().size());
        for (auto i : p.getChanged())
            changed.append(readItem(i));
        QList<quint32> removed;
        for (auto id : p.getRemoved())
            removed.append(id);
        m_connection->toGui([c = m_connection, changed = std::move(changed), removed = std::move(removed)] { c->applyBatch(changed, removed); });
        return kj::READY_NOW;
    }

private:
    TrayConnection *m_connection;
};

class MenuListener final : public C::MenuListener::Server
{
public:
    MenuListener(TrayConnection *connection, quint64 menu)
        : m_connection(connection)
        , m_menu(menu)
    {
    }

protected:
    kj::Promise<void> layout(LayoutContext context) override
    {
        MenuEntries entries = readEntries(context.getParams().getEntries());
        m_connection->toGui([c = m_connection, menu = m_menu, entries = std::move(entries)] { Q_EMIT c->menuLayout(menu, entries); });
        return kj::READY_NOW;
    }

    kj::Promise<void> closed(ClosedContext) override
    {
        m_connection->toGui([c = m_connection, menu = m_menu] { c->closeMenu(menu); });
        return kj::READY_NOW;
    }

private:
    TrayConnection *m_connection;
    quint64 m_menu;
};

TrayConnection::TrayConnection(const QString &socketPath, QObject *parent)
    : ServiceLink(socketPath, QStringLiteral("Maia.Tray"), parent)
{
    // Menus do not outlive their connection
    connect(this, &ServiceLink::connectedChanged, this, [this] {
        if (isConnected())
            return;
        const QList<quint64> open = std::exchange(m_openMenus, {});
        for (quint64 menu : open)
            Q_EMIT menuClosed(menu);
    });
    start();
}

TrayConnection::~TrayConnection()
{
    stop();
    if (s_instance == this)
        s_instance = nullptr;
}

TrayConnection *TrayConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new TrayConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString TrayConnection::defaultSocketPath()
{
    return socketPathFor("MAIA_TRAY_SOCKET", QStringLiteral("tray"));
}

const ItemData *TrayConnection::find(quint32 id) const
{
    auto it = m_items.constFind(id);
    return it == m_items.constEnd() ? nullptr : &*it;
}

// --- KJ thread ---

void TrayConnection::connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks)
{
    m_host = bootstrap.castAs<C::TrayHost>();
    auto watch = m_host->watchRequest();
    watch.setListener(kj::heap<ShellListener>(this));
    auto watched = watch.send();
    // Kept for the whole connection: releasing it would stop the listener
    m_subscription = watched.getSubscription();
    tasks.add(watched.ignoreResult());
}

void TrayConnection::disconnected()
{
    m_menus.clear();
    m_subscription.reset();
    m_host.reset();
}

// --- GUI thread: the state ---

void TrayConnection::applySnapshot(const QList<ItemData> &items)
{
    m_items.clear();
    m_items.reserve(items.size());
    for (const auto &item : items)
        m_items.insert(item.id, item);
    Q_EMIT reset();
}

void TrayConnection::applyBatch(const QList<ItemData> &changed, const QList<quint32> &removed)
{
    for (quint32 id : removed)
        m_items.remove(id);
    for (const auto &item : changed)
        m_items.insert(item.id, item);
    Q_EMIT batch(changed, removed);
}

// --- Requests (GUI thread) ---

void TrayConnection::click(const char *what, quint32 id, int x, int y, const QString &activationToken, bool secondary)
{
    post([this, what, id, x, y, secondary, token = activationToken.toUtf8()](kj::TaskSet &tasks) {
        if (secondary) {
            auto call = m_host->secondaryActivateRequest();
            call.setId(id);
            call.setX(x);
            call.setY(y);
            call.setActivationToken(token.constData());
            tasks.add(call.send().then([what](auto &&response) { logResult(what, response); }));
        } else {
            auto call = m_host->activateRequest();
            call.setId(id);
            call.setX(x);
            call.setY(y);
            call.setActivationToken(token.constData());
            tasks.add(call.send().then([what](auto &&response) { logResult(what, response); }));
        }
    });
}

void TrayConnection::activate(quint32 id, int x, int y, const QString &activationToken)
{
    click("activate", id, x, y, activationToken, false);
}

void TrayConnection::secondaryActivate(quint32 id, int x, int y, const QString &activationToken)
{
    click("secondaryActivate", id, x, y, activationToken, true);
}

void TrayConnection::contextMenu(quint32 id, int x, int y)
{
    post([this, id, x, y](kj::TaskSet &tasks) {
        auto call = m_host->contextMenuRequest();
        call.setId(id);
        call.setX(x);
        call.setY(y);
        tasks.add(call.send().then([](auto &&response) { logResult("contextMenu", response); }));
    });
}

void TrayConnection::scroll(quint32 id, int delta, bool horizontal)
{
    post([this, id, delta, horizontal](kj::TaskSet &tasks) {
        auto call = m_host->scrollRequest();
        call.setId(id);
        call.setDelta(delta);
        call.setOrientation(horizontal ? C::Orientation::HORIZONTAL : C::Orientation::VERTICAL);
        tasks.add(call.send().then([](auto &&response) { logResult("scroll", response); }));
    });
}

quint64 TrayConnection::openMenu(quint32 id)
{
    if (!isConnected())
        return 0;
    const quint64 menu = ++m_nextMenu;
    m_openMenus.append(menu);
    post([this, id, menu](kj::TaskSet &tasks) {
        auto call = m_host->openMenuRequest();
        call.setId(id);
        call.setListener(kj::heap<MenuListener>(this, menu));
        auto sent = call.send();
        // Pipelined: usable (and closable) before the answer comes
        m_menus.emplace(menu, sent.getMenu());
        tasks.add(sent.then([this, menu](auto &&response) {
            if (response.getResult().getError() == C::ErrorCode::NONE)
                return;
            logResult("openMenu", response);
            m_menus.erase(menu);
            toGui([this, menu] { closeMenu(menu); });
        }));
    });
    return menu;
}

void TrayConnection::closeMenu(quint64 menu)
{
    if (!m_openMenus.removeOne(menu))
        return;
    // Dropping the Menu closes it for the application
    post([this, menu](kj::TaskSet &) { m_menus.erase(menu); });
    Q_EMIT menuClosed(menu);
}

void TrayConnection::menuAboutToShow(quint64 menu, int entryId)
{
    post([this, menu, entryId](kj::TaskSet &tasks) {
        auto it = m_menus.find(menu);
        if (it == m_menus.end())
            return;
        auto call = it->second.aboutToShowRequest();
        call.setEntryId(entryId);
        tasks.add(call.send().ignoreResult());
    });
}

void TrayConnection::menuSubmenuClosed(quint64 menu, int entryId)
{
    post([this, menu, entryId](kj::TaskSet &tasks) {
        auto it = m_menus.find(menu);
        if (it == m_menus.end())
            return;
        auto call = it->second.submenuClosedRequest();
        call.setEntryId(entryId);
        tasks.add(call.send().ignoreResult());
    });
}

void TrayConnection::menuActivate(quint64 menu, int entryId, const QString &activationToken)
{
    post([this, menu, entryId, token = activationToken.toUtf8()](kj::TaskSet &tasks) {
        auto it = m_menus.find(menu);
        if (it == m_menus.end())
            return;
        auto call = it->second.activateRequest();
        call.setEntryId(entryId);
        call.setActivationToken(token.constData());
        tasks.add(call.send().then([](auto &&response) { logResult("menu activate", response); }));
    });
}

} // namespace MaiaTray
