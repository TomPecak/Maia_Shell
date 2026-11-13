#include "NotificationPopups.h"

#include "CenterConnection.h"
#include "NotificationRoles.h"

#include <algorithm>
#include <limits>

namespace MaiaNotifications {

namespace {
constexpr int kCritical = int(C::Urgency::CRITICAL);
}

NotificationPopups::NotificationPopups(QObject *parent)
    : QAbstractListModel(parent)
{
    m_timer.setSingleShot(true);
    // Precise: a popup's end is visible
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &NotificationPopups::timeUp);
    auto *connection = CenterConnection::instance();
    connect(connection, &CenterConnection::reset, this, &NotificationPopups::reload);
    connect(connection, &CenterConnection::batch, this, &NotificationPopups::applyBatch);
    reload();
}

int NotificationPopups::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_popups.size());
}

QVariant NotificationPopups::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    return NotificationRoles::data(m_popups.at(index.row()).data, role);
}

QHash<int, QByteArray> NotificationPopups::roleNames() const
{
    return NotificationRoles::names();
}

bool NotificationPopups::wantsPopup(const NotificationData &n) const
{
    return n.popup && !n.expired;
}

qint64 NotificationPopups::timeoutOf(const NotificationData &n) const
{
    if (n.timeout == 0)
        return -1;
    if (n.timeout < 0)
        return n.urgency == kCritical ? -1 : m_defaultTimeout;
    return std::max(n.timeout, kMinimumTimeout);
}

int NotificationPopups::rowOf(quint32 id) const
{
    for (int row = 0; row < m_popups.size(); ++row) {
        if (m_popups[row].data.id == id)
            return row;
    }
    return -1;
}

qint64 NotificationPopups::leftOf(const Popup &popup) const
{
    if (popup.remaining < 0)
        return -1;
    return m_paused ? popup.remaining : std::max<qint64>(0, popup.remaining - popup.running.elapsed());
}

void NotificationPopups::reload()
{
    // After a (re)connection: what still wants a popup, the oldest first
    beginResetModel();
    m_popups.clear();
    const int waitingBefore = int(m_waiting.size());
    m_waiting.clear();
    QList<NotificationData> wanted;
    for (const auto &n : CenterConnection::instance()->notifications()) {
        if (wantsPopup(n))
            wanted.append(n);
    }
    std::sort(wanted.begin(), wanted.end(), [](const NotificationData &a, const NotificationData &b) {
        return a.time != b.time ? a.time < b.time : a.id < b.id;
    });
    for (const auto &n : wanted)
        enqueue(n);
    endResetModel();
    fill();
    Q_EMIT countChanged();
    if (waitingBefore != m_waiting.size())
        Q_EMIT waitingChanged();
}

void NotificationPopups::applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed)
{
    const int countBefore = int(m_popups.size());
    const int waitingBefore = int(m_waiting.size());

    for (quint32 id : removed) {
        m_waiting.removeAll(id);
        const int row = rowOf(id);
        if (row >= 0)
            removeRow(row);
    }
    for (const auto &n : changed) {
        const int row = rowOf(n.id);
        if (!wantsPopup(n)) {
            m_waiting.removeAll(n.id);
            if (row >= 0)
                removeRow(row);
        } else if (row >= 0) {
            // Replaced while shown: new content, its clock starts again
            Popup &popup = m_popups[row];
            const bool newContent = n.time != popup.data.time;
            popup.data = n;
            if (newContent) {
                popup.remaining = timeoutOf(n);
                popup.running.start();
            }
            const QModelIndex at = index(row);
            Q_EMIT dataChanged(at, at);
        } else if (!m_waiting.contains(n.id)) {
            enqueue(n);
        }
    }
    fill();
    restartTimer();
    if (countBefore != m_popups.size())
        Q_EMIT countChanged();
    if (waitingBefore != m_waiting.size())
        Q_EMIT waitingChanged();
}

void NotificationPopups::enqueue(const NotificationData &n)
{
    if (n.urgency != kCritical) {
        m_waiting.append(n.id);
        return;
    }
    // Before every waiting notification that is not critical
    const auto &notifications = CenterConnection::instance()->notifications();
    int at = 0;
    while (at < m_waiting.size()) {
        auto it = notifications.constFind(m_waiting[at]);
        if (it == notifications.constEnd() || it->urgency != kCritical)
            break;
        ++at;
    }
    m_waiting.insert(at, n.id);
}

void NotificationPopups::removeRow(int row)
{
    beginRemoveRows({}, row, row);
    m_popups.removeAt(row);
    endRemoveRows();
}

void NotificationPopups::show(const NotificationData &n)
{
    Popup popup;
    popup.data = n;
    popup.remaining = timeoutOf(n);
    popup.running.start();
    const int row = int(m_popups.size());
    beginInsertRows({}, row, row);
    m_popups.append(popup);
    endInsertRows();
}

void NotificationPopups::fill()
{
    const auto &notifications = CenterConnection::instance()->notifications();
    while (m_popups.size() < m_maximumCount && !m_waiting.isEmpty()) {
        const quint32 id = m_waiting.takeFirst();
        auto it = notifications.constFind(id);
        if (it != notifications.constEnd() && wantsPopup(*it))
            show(*it);
    }
    restartTimer();
}

void NotificationPopups::restartTimer()
{
    if (m_paused) {
        m_timer.stop();
        return;
    }
    qint64 nearest = std::numeric_limits<qint64>::max();
    for (const auto &popup : m_popups) {
        const qint64 left = leftOf(popup);
        if (left >= 0)
            nearest = std::min(nearest, left);
    }
    if (nearest == std::numeric_limits<qint64>::max())
        m_timer.stop();
    else
        m_timer.start(int(nearest));
}

void NotificationPopups::timeUp()
{
    const int countBefore = int(m_popups.size());
    const int waitingBefore = int(m_waiting.size());
    QList<quint32> over;
    for (int row = int(m_popups.size()) - 1; row >= 0; --row) {
        if (leftOf(m_popups[row]) == 0) {
            over.append(m_popups[row].data.id);
            removeRow(row);
        }
    }
    for (quint32 id : over)
        CenterConnection::instance()->expire(id);
    fill();
    if (countBefore != m_popups.size())
        Q_EMIT countChanged();
    if (waitingBefore != m_waiting.size())
        Q_EMIT waitingChanged();
}

void NotificationPopups::hide(uint notificationId)
{
    const int row = rowOf(notificationId);
    if (row < 0)
        return;
    const int waitingBefore = int(m_waiting.size());
    removeRow(row);
    CenterConnection::instance()->expire(notificationId);
    fill();
    Q_EMIT countChanged();
    if (waitingBefore != m_waiting.size())
        Q_EMIT waitingChanged();
}

void NotificationPopups::setMaximumCount(int count)
{
    count = std::max(1, count);
    if (m_maximumCount == count)
        return;
    m_maximumCount = count;
    Q_EMIT maximumCountChanged();
    const int countBefore = int(m_popups.size());
    // Fewer places: the newest wait again, in front
    while (m_popups.size() > m_maximumCount) {
        m_waiting.prepend(m_popups.last().data.id);
        removeRow(int(m_popups.size()) - 1);
    }
    fill();
    if (countBefore != m_popups.size())
        Q_EMIT countChanged();
    Q_EMIT waitingChanged();
}

void NotificationPopups::setDefaultTimeout(int ms)
{
    ms = std::max(ms, kMinimumTimeout);
    if (m_defaultTimeout == ms)
        return;
    m_defaultTimeout = ms;
    Q_EMIT defaultTimeoutChanged();
}

void NotificationPopups::setPaused(bool paused)
{
    if (m_paused == paused)
        return;
    if (paused) {
        // Stop every clock where it is
        for (auto &popup : m_popups) {
            if (popup.remaining >= 0)
                popup.remaining = std::max<qint64>(0, popup.remaining - popup.running.elapsed());
        }
    } else {
        for (auto &popup : m_popups)
            popup.running.start();
    }
    m_paused = paused;
    restartTimer();
    Q_EMIT pausedChanged();
}

} // namespace MaiaNotifications
