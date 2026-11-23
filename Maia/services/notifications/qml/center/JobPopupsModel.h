#pragma once

// JobPopupsModel: the jobs a shell shows on screen now (a card, a "live activity"), next to
// JobsModel, which is the whole list. Its rules are those NotificationPopupsModel has for
// notifications, so a shell only draws:
//
//   JobPopupsModel { id: live; maximumCount: 1; paused: card.hovered; suppressed: fullscreen.active }
//   ListView { model: live; delegate: Pill { title: model.title; percent: model.percent } }
//   Text { text: qsTr("%1 more").arg(live.waiting) }
//
// The oldest running job first, so that what the user is watching does not change places when
// another one starts. A job that ends on screen stays a moment ("Done", longer when it failed) and
// leaves; one that ended elsewhere is in the list only. hide() takes a job off the screen, it goes
// on. While suppressed (fullscreen, the notification center open) nothing is shown, and what ends
// meanwhile does not come back afterwards.
//
// Roles: those of JobsModel. An update tells only the roles that changed.

#include "NotificationData.h"

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class JobPopupsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int maximumCount READ maximumCount WRITE setMaximumCount NOTIFY maximumCountChanged)
    // How long a job that ended stays on screen (ms), and one that failed
    Q_PROPERTY(int endedTime READ endedTime WRITE setEndedTime NOTIFY endedTimeChanged)
    Q_PROPERTY(int failedTime READ failedTime WRITE setFailedTime NOTIFY failedTimeChanged)
    // The user is busy with it: the time of ended jobs stands still
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool suppressed READ suppressed WRITE setSuppressed NOTIFY suppressedChanged)
    // Running jobs without a place on screen
    Q_PROPERTY(int waiting READ waiting NOTIFY waitingChanged)

public:
    explicit JobPopupsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int maximumCount() const { return m_maximumCount; }
    void setMaximumCount(int count);
    int endedTime() const { return m_endedTime; }
    void setEndedTime(int ms);
    int failedTime() const { return m_failedTime; }
    void setFailedTime(int ms);
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    bool suppressed() const { return m_suppressed; }
    void setSuppressed(bool suppressed);
    int waiting() const { return m_waiting; }

    // Off the screen; the job goes on, in the list
    Q_INVOKABLE void hide(uint jobId);

Q_SIGNALS:
    void countChanged();
    void maximumCountChanged();
    void endedTimeChanged();
    void failedTimeChanged();
    void pausedChanged();
    void suppressedChanged();
    void waitingChanged();

private:
    void reload();
    void applyBatch(const QList<JobData> &changed, const QList<quint32> &removed);
    // Brings the rows to what should be on screen now
    void refresh();
    void update(const QList<JobData> &target);
    void restartTimer();
    void timeUp();
    bool isShown(quint32 id) const;

    QList<JobData> m_rows;
    // Seen running: its end is news
    QSet<quint32> m_watched;
    QSet<quint32> m_hidden;
    // Ended on screen. While the clock runs: when it leaves (m_clock); while paused: the ms left
    QHash<quint32, qint64> m_ending;
    QElapsedTimer m_clock;
    QTimer m_timer;
    int m_maximumCount = 1;
    int m_endedTime = 4000;
    int m_failedTime = 12000;
    int m_waiting = 0;
    bool m_paused = false;
    bool m_suppressed = false;
};

} // namespace MaiaNotifications
