#pragma once

// JobsModel: the jobs of the session (the progress of a copy in Dolphin, an archive, a download),
// the newest first, for a shell's notification center and its popups.
//
//   ListView { model: JobsModel {} delegate: JobCard { title: model.title; percent: model.percent … } }
//   ProgressRing { visible: jobs.runningCount > 0; value: jobs.percent }   // one bar for all of them
//
// runningOnly: only the jobs that run or are paused (for popups); otherwise also the finished and
// failed ones, which stay until dismissed (NotificationCenter.dismissJob). A batch of the service is
// one update of the model. Roles:
//
//   jobId, appName, desktopEntry, appIcon, title, infoMessage, state (NotificationCenter.JobState),
//   percent (-1 unknown), processedBytes, totalBytes, processedFiles, totalFiles,
//   processedDirectories, totalDirectories, processedItems, totalItems (0 = unknown), speed (bytes
//   per second), elapsed (ms), fields ([{ label, value }]), destination (a URL, "" unknown),
//   errorCode, errorText, ownerGone, killable, suspendable, started, updated (dates)

#include "NotificationData.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class JobsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(bool runningOnly READ runningOnly WRITE setRunningOnly NOTIFY runningOnlyChanged)
    // Over every job of the session, whatever the filter
    Q_PROPERTY(int runningCount READ runningCount NOTIFY summaryChanged)
    // The progress of the running jobs together, 0 .. 100; -1 when none tells it
    Q_PROPERTY(int percent READ percent NOTIFY summaryChanged)

public:
    enum Role {
        JobIdRole = Qt::UserRole + 1,
        AppNameRole,
        DesktopEntryRole,
        AppIconRole,
        TitleRole,
        InfoMessageRole,
        StateRole,
        PercentRole,
        ProcessedBytesRole,
        TotalBytesRole,
        ProcessedFilesRole,
        TotalFilesRole,
        ProcessedDirectoriesRole,
        TotalDirectoriesRole,
        ProcessedItemsRole,
        TotalItemsRole,
        SpeedRole,
        ElapsedRole,
        FieldsRole,
        DestinationRole,
        ErrorCodeRole,
        ErrorTextRole,
        OwnerGoneRole,
        KillableRole,
        SuspendableRole,
        StartedRole,
        UpdatedRole,
    };
    Q_ENUM(Role)

    explicit JobsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool runningOnly() const { return m_runningOnly; }
    void setRunningOnly(bool runningOnly);
    int runningCount() const { return m_runningCount; }
    int percent() const { return m_percent; }

    Q_INVOKABLE int rowOf(uint jobId) const;

Q_SIGNALS:
    void countChanged();
    void runningOnlyChanged();
    void summaryChanged();

private:
    bool accepts(const JobData &job) const;
    void reload();
    void applyBatch(const QList<JobData> &changed, const QList<quint32> &removed);
    void updateSummary();

    QList<JobData> m_items;
    bool m_runningOnly = false;
    int m_runningCount = 0;
    int m_percent = -1;
};

} // namespace MaiaNotifications
