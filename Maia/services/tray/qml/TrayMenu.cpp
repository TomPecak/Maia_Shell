#include "TrayMenu.h"

#include "Tray.h"
#include "TrayConnection.h"
#include "TrayItemsModel.h"

#include <QQmlEngine>
#include <QSet>

#include <algorithm>

namespace MaiaTray {

// --- The entries of one level ---

TrayMenuEntriesModel::TrayMenuEntriesModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TrayMenuEntriesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant TrayMenuEntriesModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    const MenuEntryData &entry = m_rows.at(index.row());
    switch (role) {
    case EntryIdRole:
        return entry.id;
    case SeparatorRole:
        return entry.separator;
    case Qt::DisplayRole:
    case LabelRole:
        return entry.label;
    case EnabledRole:
        return entry.enabled;
    case IconSourceRole:
        return TrayItemsModel::iconSource(entry.icon);
    case ToggleRole:
        return entry.toggle;
    case CheckedRole:
        return entry.checked;
    case ShortcutRole:
        return entry.shortcut;
    case SubmenuRole:
        return entry.submenu;
    }
    return {};
}

QHash<int, QByteArray> TrayMenuEntriesModel::roleNames() const
{
    return {
        {EntryIdRole, "entryId"},
        {SeparatorRole, "separator"},
        {LabelRole, "label"},
        {EnabledRole, "enabled"},
        {IconSourceRole, "iconSource"},
        {ToggleRole, "toggle"},
        {CheckedRole, "checked"},
        {ShortcutRole, "shortcut"},
        {SubmenuRole, "submenu"},
    };
}

QList<int> TrayMenuEntriesModel::changedRoles(const MenuEntryData &a, const MenuEntryData &b)
{
    QList<int> roles;
    if (a.separator != b.separator)
        roles.append(SeparatorRole);
    if (a.label != b.label)
        roles.append({LabelRole, Qt::DisplayRole});
    if (a.enabled != b.enabled)
        roles.append(EnabledRole);
    if (a.icon != b.icon)
        roles.append(IconSourceRole);
    if (a.toggle != b.toggle)
        roles.append(ToggleRole);
    if (a.checked != b.checked)
        roles.append(CheckedRole);
    if (a.shortcut != b.shortcut)
        roles.append(ShortcutRole);
    if (a.submenu != b.submenu)
        roles.append(SubmenuRole);
    return roles;
}

void TrayMenuEntriesModel::update(const MenuEntries &target)
{
    const int countBefore = int(m_rows.size());
    QSet<int> wanted;
    for (const auto &entry : target)
        wanted.insert(entry.id);
    for (int row = int(m_rows.size()) - 1; row >= 0; --row) {
        if (wanted.contains(m_rows[row].id))
            continue;
        beginRemoveRows({}, row, row);
        m_rows.erase(m_rows.begin() + row);
        endRemoveRows();
    }
    for (int i = 0; i < int(target.size()); ++i) {
        if (i >= int(m_rows.size()) || m_rows[i].id != target[i].id) {
            const auto found = std::find_if(m_rows.begin() + std::min<int>(i, int(m_rows.size())), m_rows.end(),
                                            [id = target[i].id](const MenuEntryData &row) { return row.id == id; });
            if (found == m_rows.end()) {
                beginInsertRows({}, i, i);
                m_rows.insert(m_rows.begin() + i, target[i]);
                endInsertRows();
                continue;
            }
            const int from = int(found - m_rows.begin());
            beginMoveRows({}, from, from, {}, i);
            MenuEntryData moved = std::move(m_rows[from]);
            m_rows.erase(m_rows.begin() + from);
            m_rows.insert(m_rows.begin() + i, std::move(moved));
            endMoveRows();
        }
        const QList<int> roles = changedRoles(m_rows[i], target[i]);
        m_rows[i] = target[i];
        if (!roles.isEmpty()) {
            const QModelIndex at = index(i);
            Q_EMIT dataChanged(at, at, roles);
        }
    }
    if (countBefore != int(m_rows.size()))
        Q_EMIT countChanged();
    const bool toggles = std::any_of(m_rows.cbegin(), m_rows.cend(), [](const MenuEntryData &entry) { return entry.toggle != 0; });
    if (toggles != m_hasToggles) {
        m_hasToggles = toggles;
        Q_EMIT hasTogglesChanged();
    }
}

// --- The menu ---

TrayMenu::TrayMenu(QObject *parent)
    : QObject(parent)
    , m_entries(new TrayMenuEntriesModel(this))
{
    auto *connection = TrayConnection::instance();
    connect(connection, &TrayConnection::menuLayout, this, &TrayMenu::applyLayout);
    connect(connection, &TrayConnection::menuClosed, this, [this](quint64 menu) {
        if (menu == m_menu)
            close(true);
    });
}

TrayMenu::~TrayMenu()
{
    if (m_menu)
        TrayConnection::instance()->closeMenu(std::exchange(m_menu, 0));
}

const MenuEntries *TrayMenu::childrenOf(const MenuEntries &entries, int id)
{
    for (const auto &entry : entries) {
        if (entry.id == id)
            return &entry.children;
        if (const MenuEntries *found = childrenOf(entry.children, id))
            return found;
    }
    return nullptr;
}

void TrayMenu::setItemId(uint id)
{
    if (m_itemId == id)
        return;
    const bool wasOpen = m_menu != 0;
    if (wasOpen)
        close(false);
    m_itemId = id;
    Q_EMIT itemIdChanged();
    if (m_active)
        open();
}

void TrayMenu::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    Q_EMIT activeChanged();
    if (active)
        open();
    else
        close(false);
}

void TrayMenu::setReady(bool ready)
{
    if (m_ready == ready)
        return;
    m_ready = ready;
    Q_EMIT readyChanged();
}

void TrayMenu::open()
{
    if (m_menu || !m_itemId)
        return;
    m_layout.clear();
    m_entries->update({});
    for (auto *submenu : std::as_const(m_submenus))
        submenu->update({});
    m_menu = TrayConnection::instance()->openMenu(m_itemId);
    if (!m_menu)
        Q_EMIT closed();
}

void TrayMenu::close(bool tellShell)
{
    if (!m_menu)
        return;
    const quint64 menu = std::exchange(m_menu, 0);
    TrayConnection::instance()->closeMenu(menu);
    setReady(false);
    if (tellShell)
        Q_EMIT closed();
}

void TrayMenu::applyLayout(quint64 menu, const MenuEntries &entries)
{
    if (menu != m_menu)
        return;
    m_layout = entries;
    m_entries->update(m_layout);
    for (auto it = m_submenus.cbegin(); it != m_submenus.cend(); ++it) {
        const MenuEntries *children = childrenOf(m_layout, it.key());
        it.value()->update(children ? *children : MenuEntries{});
    }
    setReady(true);
}

TrayMenuEntriesModel *TrayMenu::submenu(int entryId)
{
    auto *&model = m_submenus[entryId];
    if (!model) {
        model = new TrayMenuEntriesModel(this);
        // Ours: QML must not take it when the value it got is gone
        QQmlEngine::setObjectOwnership(model, QQmlEngine::CppOwnership);
        if (const MenuEntries *children = childrenOf(m_layout, entryId))
            model->update(*children);
    }
    return model;
}

void TrayMenu::aboutToShow(int entryId)
{
    if (m_menu)
        TrayConnection::instance()->menuAboutToShow(m_menu, entryId);
}

void TrayMenu::submenuClosed(int entryId)
{
    if (m_menu)
        TrayConnection::instance()->menuSubmenuClosed(m_menu, entryId);
}

void TrayMenu::trigger(int entryId, QWindow *window)
{
    if (!m_menu)
        return;
    const quint64 menu = m_menu;
    const ItemData *item = TrayConnection::instance()->find(m_itemId);
    const QString appId = item ? item->desktopEntry : QString();
    // The menu is closed for the application only after its entry is sent: the request goes first
    m_menu = 0;
    setReady(false);
    Tray::withToken(window, appId, [menu, entryId](const QString &token) {
        auto *connection = TrayConnection::instance();
        connection->menuActivate(menu, entryId, token);
        connection->closeMenu(menu);
    });
    Q_EMIT triggered(entryId);
    Q_EMIT closed();
}

} // namespace MaiaTray
