#include "NotificationsModel.h"

#include "CenterConnection.h"
#include "NotificationRoles.h"

#include <algorithm>

namespace MaiaNotifications {

NotificationsModel::NotificationsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *connection = CenterConnection::instance();
    connect(connection, &CenterConnection::reset, this, &NotificationsModel::reload);
    connect(connection, &CenterConnection::batch, this, &NotificationsModel::applyBatch);
    reload();
}

int NotificationsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant NotificationsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    return NotificationRoles::data(m_items.at(index.row()), role);
}

QHash<int, QByteArray> NotificationsModel::roleNames() const
{
    return NotificationRoles::names();
}

int NotificationsModel::rowOf(uint notificationId) const
{
    return m_rows.value(notificationId, -1);
}

void NotificationsModel::reindex()
{
    m_rows.clear();
    m_rows.reserve(m_items.size());
    for (int row = 0; row < m_items.size(); ++row)
        m_rows.insert(m_items[row].id, row);
}

void NotificationsModel::reload()
{
    beginResetModel();
    // The connection keeps the current list (the snapshot and every batch since)
    m_items = CenterConnection::instance()->notifications().values();
    std::stable_sort(m_items.begin(), m_items.end(), [](const NotificationData &a, const NotificationData &b) {
        return a.time != b.time ? a.time > b.time : a.id > b.id;
    });
    reindex();
    endResetModel();
    Q_EMIT countChanged();
}

void NotificationsModel::applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed)
{
    const int countBefore = int(m_items.size());

    // Removed rows, from the bottom, in contiguous ranges
    QList<int> rows;
    for (quint32 id : removed) {
        const int row = m_rows.value(id, -1);
        if (row >= 0)
            rows.append(row);
    }
    std::sort(rows.begin(), rows.end(), std::greater<>());
    for (int i = 0; i < rows.size();) {
        int last = rows[i];
        int first = last;
        int j = i + 1;
        while (j < rows.size() && rows[j] == first - 1) {
            first = rows[j];
            ++j;
        }
        beginRemoveRows({}, first, last);
        m_items.remove(first, last - first + 1);
        endRemoveRows();
        i = j;
    }
    if (!rows.isEmpty())
        reindex();

    // Changed: in place, or to the top when replaced (newer than the top)
    QList<NotificationData> added;
    for (const auto &n : changed) {
        const int row = m_rows.value(n.id, -1);
        if (row < 0) {
            added.append(n);
            continue;
        }
        const bool newer = n.time > m_items[row].time;
        m_items[row] = n;
        if (newer && row > 0) {
            beginMoveRows({}, row, row, {}, 0);
            m_items.move(row, 0);
            endMoveRows();
            reindex();
            const QModelIndex top = index(0);
            Q_EMIT dataChanged(top, top);
        } else {
            const QModelIndex at = index(row);
            Q_EMIT dataChanged(at, at);
        }
    }

    // New ones: one insertion at the top, the newest first
    if (!added.isEmpty()) {
        std::stable_sort(added.begin(), added.end(), [](const NotificationData &a, const NotificationData &b) {
            return a.time != b.time ? a.time > b.time : a.id > b.id;
        });
        beginInsertRows({}, 0, int(added.size()) - 1);
        m_items = added + m_items;
        endInsertRows();
        reindex();
    }

    if (countBefore != m_items.size())
        Q_EMIT countChanged();
}

} // namespace MaiaNotifications
