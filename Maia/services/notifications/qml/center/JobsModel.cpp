#include "JobsModel.h"

#include "CenterConnection.h"

#include <QDateTime>
#include <QVariantMap>

#include <algorithm>

namespace MaiaNotifications {

namespace {
bool newerFirst(const JobData &a, const JobData &b)
{
    return a.started != b.started ? a.started > b.started : a.id > b.id;
}
} // namespace

JobsModel::JobsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *connection = CenterConnection::instance();
    connect(connection, &CenterConnection::jobsReset, this, &JobsModel::reload);
    connect(connection, &CenterConnection::jobsBatch, this, &JobsModel::applyBatch);
    reload();
}

bool JobsModel::accepts(const JobData &job) const
{
    return !m_runningOnly || job.running();
}

int JobsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

int JobsModel::rowOf(uint jobId) const
{
    for (int row = 0; row < m_items.size(); ++row) {
        if (m_items[row].id == jobId)
            return row;
    }
    return -1;
}

QHash<int, QByteArray> JobsModel::roleNames() const
{
    return jobRoleNames();
}

QHash<int, QByteArray> JobsModel::jobRoleNames()
{
    return {
        {JobIdRole, "jobId"},
        {AppNameRole, "appName"},
        {DesktopEntryRole, "desktopEntry"},
        {AppIconRole, "appIcon"},
        {TitleRole, "title"},
        {InfoMessageRole, "infoMessage"},
        {StateRole, "state"},
        {PercentRole, "percent"},
        {ProcessedBytesRole, "processedBytes"},
        {TotalBytesRole, "totalBytes"},
        {ProcessedFilesRole, "processedFiles"},
        {TotalFilesRole, "totalFiles"},
        {ProcessedDirectoriesRole, "processedDirectories"},
        {TotalDirectoriesRole, "totalDirectories"},
        {ProcessedItemsRole, "processedItems"},
        {TotalItemsRole, "totalItems"},
        {SpeedRole, "speed"},
        {ElapsedRole, "elapsed"},
        {FieldsRole, "fields"},
        {DestinationRole, "destination"},
        {ErrorCodeRole, "errorCode"},
        {ErrorTextRole, "errorText"},
        {OwnerGoneRole, "ownerGone"},
        {KillableRole, "killable"},
        {SuspendableRole, "suspendable"},
        {StartedRole, "started"},
        {UpdatedRole, "updated"},
    };
}

QVariant JobsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    return jobData(m_items.at(index.row()), role);
}

QVariant JobsModel::jobData(const JobData &j, int role)
{
    switch (role) {
    case JobIdRole:
        return j.id;
    case AppNameRole:
        return j.appName;
    case DesktopEntryRole:
        return j.desktopEntry;
    case AppIconRole:
        return j.appIcon;
    case TitleRole:
        return j.title;
    case InfoMessageRole:
        return j.infoMessage;
    case StateRole:
        return j.state;
    case PercentRole:
        return j.percent;
    case ProcessedBytesRole:
        return qreal(j.processedBytes);
    case TotalBytesRole:
        return qreal(j.totalBytes);
    case ProcessedFilesRole:
        return qreal(j.processedFiles);
    case TotalFilesRole:
        return qreal(j.totalFiles);
    case ProcessedDirectoriesRole:
        return qreal(j.processedDirectories);
    case TotalDirectoriesRole:
        return qreal(j.totalDirectories);
    case ProcessedItemsRole:
        return qreal(j.processedItems);
    case TotalItemsRole:
        return qreal(j.totalItems);
    case SpeedRole:
        return qreal(j.speed);
    case ElapsedRole:
        return qreal(j.elapsed);
    case FieldsRole: {
        QVariantList list;
        for (const auto &f : j.fields)
            list.append(QVariantMap{{QStringLiteral("label"), f.label}, {QStringLiteral("value"), f.value}});
        return list;
    }
    case DestinationRole:
        return j.destination;
    case ErrorCodeRole:
        return j.errorCode;
    case ErrorTextRole:
        return j.errorText;
    case OwnerGoneRole:
        return j.ownerGone;
    case KillableRole:
        return j.killable;
    case SuspendableRole:
        return j.suspendable;
    case StartedRole:
        return QDateTime::fromMSecsSinceEpoch(j.started);
    case UpdatedRole:
        return QDateTime::fromMSecsSinceEpoch(j.updated);
    }
    return {};
}

QList<int> JobsModel::changedRoles(const JobData &a, const JobData &b)
{
    QList<int> roles;
    const auto compare = [&roles](bool same, int role) {
        if (!same)
            roles.append(role);
    };
    compare(a.id == b.id, JobIdRole);
    compare(a.appName == b.appName, AppNameRole);
    compare(a.desktopEntry == b.desktopEntry, DesktopEntryRole);
    compare(a.appIcon == b.appIcon, AppIconRole);
    compare(a.title == b.title, TitleRole);
    compare(a.infoMessage == b.infoMessage, InfoMessageRole);
    compare(a.state == b.state, StateRole);
    compare(a.percent == b.percent, PercentRole);
    compare(a.processedBytes == b.processedBytes, ProcessedBytesRole);
    compare(a.totalBytes == b.totalBytes, TotalBytesRole);
    compare(a.processedFiles == b.processedFiles, ProcessedFilesRole);
    compare(a.totalFiles == b.totalFiles, TotalFilesRole);
    compare(a.processedDirectories == b.processedDirectories, ProcessedDirectoriesRole);
    compare(a.totalDirectories == b.totalDirectories, TotalDirectoriesRole);
    compare(a.processedItems == b.processedItems, ProcessedItemsRole);
    compare(a.totalItems == b.totalItems, TotalItemsRole);
    compare(a.speed == b.speed, SpeedRole);
    compare(a.elapsed == b.elapsed, ElapsedRole);
    compare(a.fields == b.fields, FieldsRole);
    compare(a.destination == b.destination, DestinationRole);
    compare(a.errorCode == b.errorCode, ErrorCodeRole);
    compare(a.errorText == b.errorText, ErrorTextRole);
    compare(a.ownerGone == b.ownerGone, OwnerGoneRole);
    compare(a.killable == b.killable, KillableRole);
    compare(a.suspendable == b.suspendable, SuspendableRole);
    compare(a.started == b.started, StartedRole);
    compare(a.updated == b.updated, UpdatedRole);
    return roles;
}

void JobsModel::setRunningOnly(bool runningOnly)
{
    if (m_runningOnly == runningOnly)
        return;
    m_runningOnly = runningOnly;
    Q_EMIT runningOnlyChanged();
    reload();
}

void JobsModel::reload()
{
    const int countBefore = int(m_items.size());
    beginResetModel();
    m_items.clear();
    for (const auto &job : CenterConnection::instance()->jobs()) {
        if (accepts(job))
            m_items.append(job);
    }
    std::sort(m_items.begin(), m_items.end(), newerFirst);
    endResetModel();
    if (countBefore != m_items.size())
        Q_EMIT countChanged();
    updateSummary();
}

void JobsModel::applyBatch(const QList<JobData> &changed, const QList<quint32> &removed)
{
    const int countBefore = int(m_items.size());
    auto removeRow = [this](int row) {
        beginRemoveRows({}, row, row);
        m_items.removeAt(row);
        endRemoveRows();
    };
    for (quint32 id : removed) {
        const int row = rowOf(id);
        if (row >= 0)
            removeRow(row);
    }
    QList<JobData> added;
    for (const auto &job : changed) {
        const int row = rowOf(job.id);
        if (row >= 0 && !accepts(job)) {
            removeRow(row);
        } else if (row >= 0) {
            const QList<int> roles = changedRoles(m_items[row], job);
            m_items[row] = job;
            if (!roles.isEmpty()) {
                const QModelIndex at = index(row);
                Q_EMIT dataChanged(at, at, roles);
            }
        } else if (accepts(job)) {
            added.append(job);
        }
    }
    if (!added.isEmpty()) {
        // New jobs are the newest: one insertion at the top
        std::sort(added.begin(), added.end(), newerFirst);
        beginInsertRows({}, 0, int(added.size()) - 1);
        m_items = added + m_items;
        endInsertRows();
    }
    if (countBefore != m_items.size())
        Q_EMIT countChanged();
    updateSummary();
}

void JobsModel::updateSummary()
{
    int running = 0;
    quint64 processed = 0;
    quint64 total = 0;
    int percentSum = 0;
    int withPercent = 0;
    bool allBytes = true;
    for (const auto &job : CenterConnection::instance()->jobs()) {
        if (!job.running())
            continue;
        ++running;
        if (job.totalBytes > 0) {
            processed += std::min(job.processedBytes, job.totalBytes);
            total += job.totalBytes;
        } else {
            allBytes = false;
        }
        if (job.percent >= 0) {
            percentSum += job.percent;
            ++withPercent;
        }
    }
    // By bytes when every running job tells them (a big copy weighs more), else the mean
    int percent = -1;
    if (running > 0 && allBytes && total > 0)
        percent = int(processed * 100 / total);
    else if (withPercent > 0)
        percent = percentSum / withPercent;
    if (running == m_runningCount && percent == m_percent)
        return;
    m_runningCount = running;
    m_percent = percent;
    Q_EMIT summaryChanged();
}

} // namespace MaiaNotifications
