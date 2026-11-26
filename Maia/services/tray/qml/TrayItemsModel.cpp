#include "TrayItemsModel.h"

#include "TrayConnection.h"

#include <QIcon>
#include <QSet>

#include <algorithm>

namespace MaiaTray {

namespace {

bool inOrder(const ItemData &a, const ItemData &b)
{
    return a.category != b.category ? int(a.category) < int(b.category) : a.id < b.id;
}

bool passes(const ItemData &item, TrayItemsModel::Filter filter)
{
    switch (filter) {
    case TrayItemsModel::All:
        return true;
    case TrayItemsModel::Shown:
        return item.status != ItemStatus::Passive;
    case TrayItemsModel::Passive:
        return item.status == ItemStatus::Passive;
    }
    return true;
}

const IconData &currentIcon(const ItemData &item)
{
    if (item.status == ItemStatus::NeedsAttention && !item.attentionIcon.isEmpty())
        return item.attentionIcon;
    return item.icon;
}

QString currentSource(const ItemData &item)
{
    return TrayItemsModel::iconSource(currentIcon(item));
}

} // namespace

TrayItemsModel::TrayItemsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *connection = TrayConnection::instance();
    connect(connection, &TrayConnection::reset, this, &TrayItemsModel::refresh);
    connect(connection, &TrayConnection::batch, this, &TrayItemsModel::refresh);
    refresh();
}

QString TrayItemsModel::iconSource(const IconData &icon)
{
    if (!icon.name.isEmpty() && (icon.url.isEmpty() || QIcon::hasThemeIcon(icon.name)))
        return icon.name;
    return icon.url;
}

bool TrayItemsModel::iconIsMask(const IconData &icon)
{
    return icon.mask && !icon.url.isEmpty() && iconSource(icon) == icon.url;
}

QList<ItemData> TrayItemsModel::select(const QList<ItemData> &items, Filter filter, int maximumCount, int *hidden)
{
    QList<ItemData> rows;
    for (const auto &item : items) {
        if (passes(item, filter))
            rows.append(item);
    }
    std::sort(rows.begin(), rows.end(), inOrder);
    const int all = int(rows.size());
    if (maximumCount >= 0 && all > maximumCount) {
        // Attention first, then the rest in order; the chosen ones stay in order
        QList<ItemData> chosen;
        for (const auto &item : std::as_const(rows)) {
            if (chosen.size() < maximumCount && item.status == ItemStatus::NeedsAttention)
                chosen.append(item);
        }
        for (const auto &item : std::as_const(rows)) {
            if (chosen.size() < maximumCount && item.status != ItemStatus::NeedsAttention)
                chosen.append(item);
        }
        std::sort(chosen.begin(), chosen.end(), inOrder);
        rows = chosen;
    }
    if (hidden)
        *hidden = all - int(rows.size());
    return rows;
}

int TrayItemsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant TrayItemsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    const ItemData &item = m_rows.at(index.row());
    switch (role) {
    case ItemIdRole:
        return item.id;
    case KeyRole:
        return item.key;
    case Qt::DisplayRole:
    case TitleRole:
        return item.title;
    case StatusRole:
        return int(item.status);
    case CategoryRole:
        return int(item.category);
    case NeedsAttentionRole:
        return item.status == ItemStatus::NeedsAttention;
    case IconNameRole:
        return item.icon.name;
    case IconUrlRole:
        return item.icon.url;
    case IconSourceRole:
        return iconSource(item.icon);
    case AttentionIconSourceRole:
        return iconSource(item.attentionIcon);
    case OverlayIconSourceRole:
        return iconSource(item.overlayIcon);
    case CurrentIconSourceRole:
        return currentSource(item);
    case ToolTipTitleRole:
        return item.toolTipTitle;
    case ToolTipTextRole:
        return item.toolTipText;
    case ToolTipIconSourceRole:
        return iconSource(item.toolTipIcon);
    case HasMenuRole:
        return item.hasMenu;
    case ItemIsMenuRole:
        return item.itemIsMenu;
    case DesktopEntryRole:
        return item.desktopEntry;
    case AppNameRole:
        return item.appName;
    case AppIconRole:
        return item.appIcon;
    case IconIsMaskRole:
        return iconIsMask(item.icon);
    case CurrentIconIsMaskRole:
        return iconIsMask(currentIcon(item));
    }
    return {};
}

QHash<int, QByteArray> TrayItemsModel::roleNames() const
{
    return {
        {ItemIdRole, "itemId"},
        {KeyRole, "key"},
        {TitleRole, "title"},
        {StatusRole, "status"},
        {CategoryRole, "category"},
        {NeedsAttentionRole, "needsAttention"},
        {IconNameRole, "iconName"},
        {IconUrlRole, "iconUrl"},
        {IconSourceRole, "iconSource"},
        {AttentionIconSourceRole, "attentionIconSource"},
        {OverlayIconSourceRole, "overlayIconSource"},
        {CurrentIconSourceRole, "currentIconSource"},
        {ToolTipTitleRole, "toolTipTitle"},
        {ToolTipTextRole, "toolTipText"},
        {ToolTipIconSourceRole, "toolTipIconSource"},
        {HasMenuRole, "hasMenu"},
        {ItemIsMenuRole, "itemIsMenu"},
        {DesktopEntryRole, "desktopEntry"},
        {AppNameRole, "appName"},
        {AppIconRole, "appIcon"},
        {IconIsMaskRole, "iconIsMask"},
        {CurrentIconIsMaskRole, "currentIconIsMask"},
    };
}

QVariantMap TrayItemsModel::get(int row) const
{
    QVariantMap map;
    if (row < 0 || row >= m_rows.size())
        return map;
    const QModelIndex at = index(row);
    const auto names = roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it)
        map.insert(QString::fromLatin1(it.value()), data(at, it.key()));
    return map;
}

QList<int> TrayItemsModel::changedRoles(const ItemData &a, const ItemData &b)
{
    QList<int> roles;
    auto check = [&roles](bool changed, std::initializer_list<int> list) {
        if (changed)
            roles.append(list);
    };
    check(a.key != b.key, {KeyRole});
    check(a.title != b.title, {TitleRole, Qt::DisplayRole});
    check(a.status != b.status, {StatusRole, NeedsAttentionRole});
    check(a.category != b.category, {CategoryRole});
    check(a.icon != b.icon, {IconNameRole, IconUrlRole, IconSourceRole, IconIsMaskRole});
    check(a.attentionIcon != b.attentionIcon, {AttentionIconSourceRole});
    check(a.overlayIcon != b.overlayIcon, {OverlayIconSourceRole});
    check(currentSource(a) != currentSource(b), {CurrentIconSourceRole});
    check(iconIsMask(currentIcon(a)) != iconIsMask(currentIcon(b)), {CurrentIconIsMaskRole});
    check(a.toolTipTitle != b.toolTipTitle, {ToolTipTitleRole});
    check(a.toolTipText != b.toolTipText, {ToolTipTextRole});
    check(a.toolTipIcon != b.toolTipIcon, {ToolTipIconSourceRole});
    check(a.hasMenu != b.hasMenu, {HasMenuRole});
    check(a.itemIsMenu != b.itemIsMenu, {ItemIsMenuRole});
    check(a.desktopEntry != b.desktopEntry, {DesktopEntryRole});
    check(a.appName != b.appName, {AppNameRole});
    check(a.appIcon != b.appIcon, {AppIconRole});
    return roles;
}

void TrayItemsModel::refresh()
{
    const int countBefore = int(m_rows.size());
    const int attentionBefore = m_attentionCount;
    int hidden = 0;
    const QList<ItemData> target = select(TrayConnection::instance()->items().values(), m_filter, m_maximumCount, &hidden);

    QSet<quint32> wanted;
    wanted.reserve(target.size());
    for (const auto &item : target)
        wanted.insert(item.id);
    for (int row = int(m_rows.size()) - 1; row >= 0; --row) {
        if (wanted.contains(m_rows[row].id))
            continue;
        beginRemoveRows({}, row, row);
        m_rows.removeAt(row);
        endRemoveRows();
    }

    for (int i = 0; i < target.size(); ++i) {
        if (i >= m_rows.size() || m_rows[i].id != target[i].id) {
            const auto found = std::find_if(m_rows.cbegin() + std::min<qsizetype>(i, m_rows.size()), m_rows.cend(),
                                            [id = target[i].id](const ItemData &row) { return row.id == id; });
            if (found == m_rows.cend()) {
                beginInsertRows({}, i, i);
                m_rows.insert(i, target[i]);
                endInsertRows();
                continue;
            }
            // Its category changed: it moves to its new place
            const int from = int(found - m_rows.cbegin());
            beginMoveRows({}, from, from, {}, i);
            m_rows.move(from, i);
            endMoveRows();
        }
        const QList<int> roles = changedRoles(m_rows[i], target[i]);
        m_rows[i] = target[i];
        if (!roles.isEmpty()) {
            const QModelIndex at = index(i);
            Q_EMIT dataChanged(at, at, roles);
        }
    }

    m_attentionCount = int(std::count_if(m_rows.cbegin(), m_rows.cend(), [](const ItemData &item) { return item.status == ItemStatus::NeedsAttention; }));
    if (countBefore != m_rows.size())
        Q_EMIT countChanged();
    if (attentionBefore != m_attentionCount)
        Q_EMIT attentionCountChanged();
    if (m_hiddenCount != hidden) {
        m_hiddenCount = hidden;
        Q_EMIT hiddenCountChanged();
    }
}

void TrayItemsModel::setFilter(Filter filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    Q_EMIT filterChanged();
    refresh();
}

void TrayItemsModel::setMaximumCount(int count)
{
    count = std::max(-1, count);
    if (m_maximumCount == count)
        return;
    m_maximumCount = count;
    Q_EMIT maximumCountChanged();
    refresh();
}

} // namespace MaiaTray
