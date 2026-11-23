#include "JobPopupsModel.h"

#include "CenterConnection.h"
#include "JobsModel.h"

#include <algorithm>
#include <limits>

namespace MaiaNotifications {

namespace {
constexpr int kFailed = 3;
}

JobPopupsModel::JobPopupsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_clock.start();
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &JobPopupsModel::timeUp);
    auto *connection = CenterConnection::instance();
    connect(connection, &CenterConnection::jobsReset, this, &JobPopupsModel::reload);
    connect(connection, &CenterConnection::jobsBatch, this, &JobPopupsModel::applyBatch);
    reload();
}

int JobPopupsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant JobPopupsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    return JobsModel::jobData(m_rows.at(index.row()), role);
}

QHash<int, QByteArray> JobPopupsModel::roleNames() const
{
    return JobsModel::jobRoleNames();
}

bool JobPopupsModel::isShown(quint32 id) const
{
    return std::any_of(m_rows.cbegin(), m_rows.cend(), [id](const JobData &job) { return job.id == id; });
}

void JobPopupsModel::reload()
{
    // After a (re)connection: what ended before is not news
    const auto &jobs = CenterConnection::instance()->jobs();
    m_watched.clear();
    m_ending.clear();
    for (const auto &job : jobs) {
        if (job.running())
            m_watched.insert(job.id);
    }
    for (auto it = m_hidden.begin(); it != m_hidden.end();) {
        if (jobs.contains(*it))
            ++it;
        else
            it = m_hidden.erase(it);
    }
    refresh();
}

void JobPopupsModel::applyBatch(const QList<JobData> &changed, const QList<quint32> &removed)
{
    for (quint32 id : removed) {
        m_watched.remove(id);
        m_hidden.remove(id);
        m_ending.remove(id);
    }
    for (const auto &job : changed) {
        if (job.running()) {
            m_watched.insert(job.id);
            m_ending.remove(job.id);
        } else if (m_watched.remove(job.id) && !m_suppressed && isShown(job.id)) {
            const qint64 time = job.state == kFailed ? m_failedTime : m_endedTime;
            m_ending.insert(job.id, m_paused ? time : m_clock.elapsed() + time);
        }
    }
    refresh();
}

void JobPopupsModel::refresh()
{
    QList<JobData> wanted;
    if (!m_suppressed) {
        for (const auto &job : CenterConnection::instance()->jobs()) {
            if (!m_hidden.contains(job.id) && (job.running() || m_ending.contains(job.id)))
                wanted.append(job);
        }
        std::sort(wanted.begin(), wanted.end(), [](const JobData &a, const JobData &b) {
            return a.started != b.started ? a.started < b.started : a.id < b.id;
        });
    }
    const int shown = std::min(m_maximumCount, int(wanted.size()));
    const int waiting = int(std::count_if(wanted.cbegin() + shown, wanted.cend(),
                                          [](const JobData &job) { return job.running(); }));
    wanted.resize(shown);
    update(wanted);
    if (m_waiting != waiting) {
        m_waiting = waiting;
        Q_EMIT waitingChanged();
    }
    restartTimer();
}

void JobPopupsModel::update(const QList<JobData> &target)
{
    const int countBefore = int(m_rows.size());

    QSet<quint32> wanted;
    wanted.reserve(target.size());
    for (const JobData &job : target)
        wanted.insert(job.id);
    for (int row = int(m_rows.size()) - 1; row >= 0; --row) {
        if (wanted.contains(m_rows[row].id))
            continue;
        beginRemoveRows({}, row, row);
        m_rows.removeAt(row);
        endRemoveRows();
    }

    // What stays is in the target's order (both by age): only insertions and changes in place
    for (int i = 0; i < target.size(); ++i) {
        if (i < m_rows.size() && m_rows[i].id == target[i].id) {
            const QList<int> roles = JobsModel::changedRoles(m_rows[i], target[i]);
            m_rows[i] = target[i];
            if (!roles.isEmpty()) {
                const QModelIndex at = index(i);
                Q_EMIT dataChanged(at, at, roles);
            }
        } else {
            beginInsertRows({}, i, i);
            m_rows.insert(i, target[i]);
            endInsertRows();
        }
    }

    if (countBefore != m_rows.size())
        Q_EMIT countChanged();
}

void JobPopupsModel::restartTimer()
{
    if (m_paused || m_ending.isEmpty()) {
        m_timer.stop();
        return;
    }
    qint64 nearest = std::numeric_limits<qint64>::max();
    for (qint64 until : std::as_const(m_ending))
        nearest = std::min(nearest, until);
    m_timer.start(int(std::max<qint64>(0, nearest - m_clock.elapsed())));
}

void JobPopupsModel::timeUp()
{
    const qint64 now = m_clock.elapsed();
    for (auto it = m_ending.begin(); it != m_ending.end();) {
        if (it.value() <= now)
            it = m_ending.erase(it);
        else
            ++it;
    }
    refresh();
}

void JobPopupsModel::hide(uint jobId)
{
    m_hidden.insert(jobId);
    m_ending.remove(jobId);
    refresh();
}

void JobPopupsModel::setMaximumCount(int count)
{
    count = std::max(1, count);
    if (m_maximumCount == count)
        return;
    m_maximumCount = count;
    Q_EMIT maximumCountChanged();
    refresh();
}

void JobPopupsModel::setEndedTime(int ms)
{
    ms = std::max(0, ms);
    if (m_endedTime == ms)
        return;
    m_endedTime = ms;
    Q_EMIT endedTimeChanged();
}

void JobPopupsModel::setFailedTime(int ms)
{
    ms = std::max(0, ms);
    if (m_failedTime == ms)
        return;
    m_failedTime = ms;
    Q_EMIT failedTimeChanged();
}

void JobPopupsModel::setPaused(bool paused)
{
    if (m_paused == paused)
        return;
    const qint64 now = m_clock.elapsed();
    // "When it leaves" becomes "how long it has left", and back
    for (auto it = m_ending.begin(); it != m_ending.end(); ++it)
        it.value() = paused ? std::max<qint64>(0, it.value() - now) : now + it.value();
    m_paused = paused;
    restartTimer();
    Q_EMIT pausedChanged();
}

void JobPopupsModel::setSuppressed(bool suppressed)
{
    if (m_suppressed == suppressed)
        return;
    m_suppressed = suppressed;
    if (suppressed)
        m_ending.clear();
    refresh();
    Q_EMIT suppressedChanged();
}

} // namespace MaiaNotifications
