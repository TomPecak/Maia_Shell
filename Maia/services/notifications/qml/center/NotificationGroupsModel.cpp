#include "NotificationGroupsModel.h"

#include "CenterConnection.h"

#include <algorithm>

namespace MaiaNotifications {

namespace {

QString groupOf(const NotificationData &n)
{
    return n.desktopEntry.isEmpty() ? n.appName : n.desktopEntry;
}

} // namespace

NotificationGroupsModel::NotificationGroupsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *connection = CenterConnection::instance();
    connect(connection, &CenterConnection::reset, this, &NotificationGroupsModel::reload);
    connect(connection, &CenterConnection::batch, this, &NotificationGroupsModel::applyBatch);
    reload();
}

int NotificationGroupsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant NotificationGroupsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    const Row &row = m_rows.at(index.row());
    switch (role) {
    case GroupKeyRole:
        return row.key;
    case GroupCountRole:
        return row.groupCount;
    case GroupHeadRole:
        return row.head;
    case GroupExpandedRole:
        return row.expanded;
    default:
        return NotificationRoles::data(row.data, role);
    }
}

QHash<int, QByteArray> NotificationGroupsModel::roleNames() const
{
    QHash<int, QByteArray> names = NotificationRoles::names();
    names.insert(GroupKeyRole, "groupKey");
    names.insert(GroupCountRole, "groupCount");
    names.insert(GroupHeadRole, "groupHead");
    names.insert(GroupExpandedRole, "groupExpanded");
    return names;
}

QList<NotificationGroupsModel::Row> NotificationGroupsModel::arranged()
{
    const auto &all = CenterConnection::instance()->notifications();
    QList<const NotificationData *> newestFirst;
    newestFirst.reserve(all.size());
    for (const auto &n : all)
        newestFirst.append(&n);
    std::sort(newestFirst.begin(), newestFirst.end(), [](const NotificationData *a, const NotificationData *b) {
        return a->time != b->time ? a->time > b->time : a->id > b->id;
    });

    QStringList order;
    QHash<QString, QList<const NotificationData *>> groups;
    for (const NotificationData *n : std::as_const(newestFirst)) {
        const QString key = groupOf(*n);
        auto it = groups.find(key);
        if (it == groups.end()) {
            order.append(key);
            it = groups.insert(key, {});
        }
        it->append(n);
    }

    // A group of one has nothing to unfold, and one that is gone does not come back expanded
    for (auto it = m_expanded.begin(); it != m_expanded.end();) {
        const auto group = groups.constFind(*it);
        if (group == groups.constEnd() || group->size() < 2)
            it = m_expanded.erase(it);
        else
            ++it;
    }

    QList<Row> rows;
    rows.reserve(order.size());
    for (const QString &key : std::as_const(order)) {
        const auto &group = groups[key];
        const bool expanded = m_expanded.contains(key);
        const int shown = expanded ? int(group.size()) : 1;
        for (int i = 0; i < shown; ++i)
            rows.append({*group[i], key, int(group.size()), i == 0, expanded});
    }
    return rows;
}

void NotificationGroupsModel::reload()
{
    beginResetModel();
    m_rows = arranged();
    endResetModel();
    Q_EMIT countChanged();
    recount();
}

void NotificationGroupsModel::applyBatch(const QList<NotificationData> &changed, const QList<quint32> &)
{
    QSet<quint32> ids;
    ids.reserve(changed.size());
    for (const auto &n : changed)
        ids.insert(n.id);
    update(arranged(), ids);
    recount();
}

void NotificationGroupsModel::update(const QList<Row> &target, const QSet<quint32> &changed)
{
    const int countBefore = int(m_rows.size());

    QSet<quint32> wanted;
    wanted.reserve(target.size());
    for (const Row &row : target)
        wanted.insert(row.data.id);

    // What is gone, from the bottom, in contiguous ranges
    for (int last = int(m_rows.size()) - 1; last >= 0; --last) {
        if (wanted.contains(m_rows[last].data.id))
            continue;
        int first = last;
        while (first > 0 && !wanted.contains(m_rows[first - 1].data.id))
            --first;
        beginRemoveRows({}, first, last);
        m_rows.remove(first, last - first + 1);
        endRemoveRows();
        last = first;
    }

    // Everything left is wanted: walk the target, moving or inserting what is not in its place
    QSet<quint32> present;
    present.reserve(m_rows.size());
    for (const Row &row : std::as_const(m_rows))
        present.insert(row.data.id);
    for (int i = 0; i < target.size(); ++i) {
        const quint32 id = target[i].data.id;
        if (i < m_rows.size() && m_rows[i].data.id == id)
            continue;
        if (present.contains(id)) {
            int from = i + 1;
            while (m_rows[from].data.id != id)
                ++from;
            beginMoveRows({}, from, from, {}, i);
            m_rows.move(from, i);
            endMoveRows();
            continue;
        }
        int end = i + 1;
        while (end < target.size() && !present.contains(target[end].data.id))
            ++end;
        beginInsertRows({}, i, end - 1);
        m_rows.insert(i, end - i, Row{});
        for (int at = i; at < end; ++at)
            m_rows[at] = target[at];
        endInsertRows();
        i = end - 1;
    }

    // In place: new content, or only what the row says about its group
    static const QList<int> groupRoles{GroupCountRole, GroupHeadRole, GroupExpandedRole};
    for (int i = 0; i < target.size(); ++i) {
        Row &row = m_rows[i];
        const Row &now = target[i];
        const bool newContent = changed.contains(now.data.id);
        const bool newGroup = row.groupCount != now.groupCount || row.head != now.head || row.expanded != now.expanded;
        if (!newContent && !newGroup)
            continue;
        row = now;
        const QModelIndex at = index(i);
        Q_EMIT dataChanged(at, at, newContent ? QList<int>{} : groupRoles);
    }

    if (countBefore != m_rows.size())
        Q_EMIT countChanged();
}

void NotificationGroupsModel::recount()
{
    const auto &all = CenterConnection::instance()->notifications();
    int unseen = 0;
    for (const auto &n : all) {
        if (double(n.time) > m_seenUntil)
            ++unseen;
    }
    if (m_total != all.size()) {
        m_total = int(all.size());
        Q_EMIT totalChanged();
    }
    if (m_unseen != unseen) {
        m_unseen = unseen;
        Q_EMIT unseenChanged();
    }
}

void NotificationGroupsModel::setSeenUntil(double ms)
{
    if (m_seenUntil == ms)
        return;
    m_seenUntil = ms;
    Q_EMIT seenUntilChanged();
    recount();
}

void NotificationGroupsModel::setGroupExpanded(const QString &key, bool expanded)
{
    if (m_expanded.contains(key) == expanded)
        return;
    if (expanded)
        m_expanded.insert(key);
    else
        m_expanded.remove(key);
    update(arranged(), {});
}

void NotificationGroupsModel::toggleGroup(const QString &key)
{
    setGroupExpanded(key, !m_expanded.contains(key));
}

void NotificationGroupsModel::collapseAll()
{
    if (m_expanded.isEmpty())
        return;
    m_expanded.clear();
    update(arranged(), {});
}

void NotificationGroupsModel::dismissGroup(const QString &key)
{
    auto *connection = CenterConnection::instance();
    QList<quint32> ids;
    for (const auto &n : connection->notifications()) {
        if (groupOf(n) == key)
            ids.append(n.id);
    }
    for (quint32 id : std::as_const(ids))
        connection->dismiss(id);
}

} // namespace MaiaNotifications
