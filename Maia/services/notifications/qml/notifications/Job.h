#pragma once

// Job: a long operation of a program (a copy, an export, a download), shown by the shell with its
// progress, as KDE applications' jobs are (a card while it runs, a ring by the clock).
//
//   import Maia.Notifications
//
//   Job {
//       id: export
//       title: qsTr("Exporting")
//       infoMessage: qsTr("Exporting %1").arg(file)
//       killable: true
//       suspendable: true
//       processedBytes: exporter.written
//       totalBytes: exporter.size
//       speed: exporter.bytesPerSecond
//       destination: folderUrl
//       onCancelRequested: { exporter.stop(); export.cancel() }
//       onSuspendRequested: { exporter.pause(); export.suspended = true }
//       onResumeRequested: { exporter.resume(); export.suspended = false }
//   }
//   … export.start();  …  export.finish()  /  export.finish(qsTr("The disk is full"))
//
// While it runs, a change of its progress goes to the service at most every kUpdateInterval (the
// shell shows it at most four times a second anyway). The program name, desktop entry, icon,
// killable, suspendable, immediate and transient count when it starts. The service shows a job
// 0.5 s after it starts (a short one never flickers), unless it is immediate.
//
// The end: finish() (done, or failed with a text), cancel() (stopped: gone without a trace).
// Destroying the object while it runs ends the job as failed, as does the program's exit. Without
// the service (the session is starting, the service restarts) the job goes out when it comes.

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

struct JobProgressData;
struct JobRequestData;

class Job : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString appName READ appName WRITE setAppName NOTIFY changed)
    Q_PROPERTY(QString desktopEntry READ desktopEntry WRITE setDesktopEntry NOTIFY changed)
    // A theme icon name or a file URL; "" the desktop entry's
    Q_PROPERTY(QString iconName READ iconName WRITE setIconName NOTIFY changed)
    // The user may cancel it (cancelRequested), pause it (suspendRequested, resumeRequested)
    Q_PROPERTY(bool killable READ killable WRITE setKillable NOTIFY changed)
    Q_PROPERTY(bool suspendable READ suspendable WRITE setSuspendable NOTIFY changed)
    // Shown at once, not after 0.5 s
    Q_PROPERTY(bool immediate READ immediate WRITE setImmediate NOTIFY changed)
    // Gone when it finishes well (kept in the list only when it fails)
    Q_PROPERTY(bool transient READ isTransient WRITE setTransient NOTIFY changed)

    // What it does ("Copying") and the current step ("Copying photo.jpg")
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY changed)
    Q_PROPERTY(QString infoMessage READ infoMessage WRITE setInfoMessage NOTIFY changed)
    // 0 .. 100; -1: from the amounts (bytes, else files, else items), unknown without them
    Q_PROPERTY(int percent READ percent WRITE setPercent NOTIFY changed)
    // Amounts: 0 = unknown
    Q_PROPERTY(qint64 processedBytes READ processedBytes WRITE setProcessedBytes NOTIFY changed)
    Q_PROPERTY(qint64 totalBytes READ totalBytes WRITE setTotalBytes NOTIFY changed)
    Q_PROPERTY(qint64 processedFiles READ processedFiles WRITE setProcessedFiles NOTIFY changed)
    Q_PROPERTY(qint64 totalFiles READ totalFiles WRITE setTotalFiles NOTIFY changed)
    Q_PROPERTY(qint64 processedDirectories READ processedDirectories WRITE setProcessedDirectories NOTIFY changed)
    Q_PROPERTY(qint64 totalDirectories READ totalDirectories WRITE setTotalDirectories NOTIFY changed)
    Q_PROPERTY(qint64 processedItems READ processedItems WRITE setProcessedItems NOTIFY changed)
    Q_PROPERTY(qint64 totalItems READ totalItems WRITE setTotalItems NOTIFY changed)
    // Bytes per second, 0 unknown
    Q_PROPERTY(qint64 speed READ speed WRITE setSpeed NOTIFY changed)
    // Lines of details: [{ label, value }], at most 8
    Q_PROPERTY(QVariantList fields READ fields WRITE setFields NOTIFY changed)
    // Where the result goes (the shell offers to open it when it is done)
    Q_PROPERTY(QUrl destination READ destination WRITE setDestination NOTIFY changed)
    // Paused: set it when the work has stopped (after suspendRequested), clear it when it goes on
    Q_PROPERTY(bool suspended READ isSuspended WRITE setSuspended NOTIFY changed)

    // Started and not ended
    Q_PROPERTY(bool running READ isRunning NOTIFY runningChanged)
    // The service's id while it runs and the service has it, 0 otherwise
    Q_PROPERTY(uint jobId READ jobId NOTIFY jobIdChanged)

public:
    // The longest a change of the progress waits before it goes to the service
    static constexpr int kUpdateInterval = 100;

    explicit Job(QObject *parent = nullptr);
    ~Job() override;

    Q_INVOKABLE void start();
    // Done (no text) or failed (with what went wrong)
    Q_INVOKABLE void finish(const QString &errorText = QString());
    // Stopped (the user's cancelRequested, or the program's own decision)
    Q_INVOKABLE void cancel();

    QString appName() const { return m_appName; }
    void setAppName(const QString &value);
    QString desktopEntry() const { return m_desktopEntry; }
    void setDesktopEntry(const QString &value);
    QString iconName() const { return m_iconName; }
    void setIconName(const QString &value);
    bool killable() const { return m_killable; }
    void setKillable(bool value);
    bool suspendable() const { return m_suspendable; }
    void setSuspendable(bool value);
    bool immediate() const { return m_immediate; }
    void setImmediate(bool value);
    bool isTransient() const { return m_transient; }
    void setTransient(bool value);

    QString title() const { return m_title; }
    void setTitle(const QString &value);
    QString infoMessage() const { return m_infoMessage; }
    void setInfoMessage(const QString &value);
    int percent() const { return m_percent; }
    void setPercent(int value);
    qint64 processedBytes() const { return m_processedBytes; }
    void setProcessedBytes(qint64 value);
    qint64 totalBytes() const { return m_totalBytes; }
    void setTotalBytes(qint64 value);
    qint64 processedFiles() const { return m_processedFiles; }
    void setProcessedFiles(qint64 value);
    qint64 totalFiles() const { return m_totalFiles; }
    void setTotalFiles(qint64 value);
    qint64 processedDirectories() const { return m_processedDirectories; }
    void setProcessedDirectories(qint64 value);
    qint64 totalDirectories() const { return m_totalDirectories; }
    void setTotalDirectories(qint64 value);
    qint64 processedItems() const { return m_processedItems; }
    void setProcessedItems(qint64 value);
    qint64 totalItems() const { return m_totalItems; }
    void setTotalItems(qint64 value);
    qint64 speed() const { return m_speed; }
    void setSpeed(qint64 value);
    QVariantList fields() const { return m_fields; }
    void setFields(const QVariantList &value);
    QUrl destination() const { return m_destination; }
    void setDestination(const QUrl &value);
    bool isSuspended() const { return m_suspended; }
    void setSuspended(bool value);

    bool isRunning() const { return m_local != 0; }
    uint jobId() const { return m_id; }

Q_SIGNALS:
    void changed();
    void runningChanged();
    void jobIdChanged();
    // The user asks: stop (then cancel()), pause (then suspended = true), go on
    void cancelRequested();
    void suspendRequested();
    void resumeRequested();

private:
    friend class NotifierConnection;
    // From the connection, for this object's job only
    void onStarted(uint id);
    void onRequest(int kind);
    // The service is gone with its jobs: the id is no more (the job goes out again when it comes)
    void onLost();

    JobRequestData request() const;
    JobProgressData progress() const;
    int percentOfAmounts() const;
    void progressChanged();
    void sendProgress();
    void end();

    QString m_appName;
    QString m_desktopEntry;
    QString m_iconName;
    bool m_killable = false;
    bool m_suspendable = false;
    bool m_immediate = false;
    bool m_transient = false;

    QString m_title;
    QString m_infoMessage;
    int m_percent = -1;
    qint64 m_processedBytes = 0;
    qint64 m_totalBytes = 0;
    qint64 m_processedFiles = 0;
    qint64 m_totalFiles = 0;
    qint64 m_processedDirectories = 0;
    qint64 m_totalDirectories = 0;
    qint64 m_processedItems = 0;
    qint64 m_totalItems = 0;
    qint64 m_speed = 0;
    QVariantList m_fields;
    QUrl m_destination;
    bool m_suspended = false;

    int m_local = 0;
    uint m_id = 0;
    QTimer m_updateTimer;
};

} // namespace MaiaNotifications
