#include "Job.h"

#include "NotificationData.h"
#include "NotifierConnection.h"

#include <QGuiApplication>
#include <QVariantMap>

namespace MaiaNotifications {

namespace {
constexpr int kMaxFields = 8;

quint64 amount(qint64 value)
{
    return quint64(qMax<qint64>(0, value));
}
} // namespace

Job::Job(QObject *parent)
    : QObject(parent)
    , m_appName(QGuiApplication::applicationDisplayName())
    , m_desktopEntry(QGuiApplication::desktopFileName())
{
    m_updateTimer.setSingleShot(true);
    m_updateTimer.setInterval(kUpdateInterval);
    connect(&m_updateTimer, &QTimer::timeout, this, &Job::sendProgress);
}

Job::~Job()
{
    // Its program let go of it: the service ends it as failed
    if (m_local != 0)
        NotifierConnection::instance()->releaseJob(m_local);
}

JobProgressData Job::progress() const
{
    JobProgressData p;
    p.title = m_title;
    p.infoMessage = m_infoMessage;
    p.percent = m_percent >= 0 ? qMin(m_percent, 100) : percentOfAmounts();
    p.processedBytes = amount(m_processedBytes);
    p.totalBytes = amount(m_totalBytes);
    p.processedFiles = amount(m_processedFiles);
    p.totalFiles = amount(m_totalFiles);
    p.processedDirectories = amount(m_processedDirectories);
    p.totalDirectories = amount(m_totalDirectories);
    p.processedItems = amount(m_processedItems);
    p.totalItems = amount(m_totalItems);
    p.speed = amount(m_speed);
    for (const QVariant &value : m_fields) {
        if (p.fields.size() == kMaxFields)
            break;
        const QVariantMap field = value.toMap();
        p.fields.append({field.value(QStringLiteral("label")).toString(), field.value(QStringLiteral("value")).toString()});
    }
    p.destination = m_destination.toString(QUrl::FullyEncoded);
    p.suspended = m_suspended;
    return p;
}

int Job::percentOfAmounts() const
{
    for (const auto &[done, total] : {std::pair{m_processedBytes, m_totalBytes}, std::pair{m_processedFiles, m_totalFiles},
                                      std::pair{m_processedItems, m_totalItems}}) {
        if (total > 0)
            return int(qBound(qint64(0), done * 100 / total, qint64(100)));
    }
    return -1;
}

JobRequestData Job::request() const
{
    JobRequestData r;
    r.appName = m_appName;
    r.desktopEntry = m_desktopEntry;
    r.appIcon = m_iconName;
    r.killable = m_killable;
    r.suspendable = m_suspendable;
    r.immediate = m_immediate;
    r.transient = m_transient;
    r.progress = progress();
    return r;
}

void Job::start()
{
    if (m_local != 0)
        return;
    m_local = NotifierConnection::instance()->startJob(this);
    Q_EMIT runningChanged();
}

void Job::progressChanged()
{
    Q_EMIT changed();
    if (m_local != 0 && !m_updateTimer.isActive())
        m_updateTimer.start();
}

void Job::sendProgress()
{
    if (m_local != 0)
        NotifierConnection::instance()->updateJob(m_local, progress());
}

void Job::finish(const QString &errorText)
{
    if (m_local == 0)
        return;
    auto *connection = NotifierConnection::instance();
    // The last state first: the shell shows what was done ("Done, 1.2 GB")
    if (m_updateTimer.isActive())
        connection->updateJob(m_local, progress());
    connection->finishJob(m_local, errorText);
    end();
}

void Job::cancel()
{
    if (m_local == 0)
        return;
    NotifierConnection::instance()->cancelJob(m_local);
    end();
}

void Job::end()
{
    m_updateTimer.stop();
    m_local = 0;
    if (m_id != 0) {
        m_id = 0;
        Q_EMIT jobIdChanged();
    }
    Q_EMIT runningChanged();
}

void Job::onStarted(uint id)
{
    if (id == m_id)
        return;
    m_id = id;
    Q_EMIT jobIdChanged();
}

void Job::onLost()
{
    if (m_id == 0)
        return;
    m_id = 0;
    Q_EMIT jobIdChanged();
}

void Job::onRequest(int kind)
{
    switch (kind) {
    case NotifierConnection::JobCancel:
        Q_EMIT cancelRequested();
        break;
    case NotifierConnection::JobSuspend:
        Q_EMIT suspendRequested();
        break;
    case NotifierConnection::JobResume:
        Q_EMIT resumeRequested();
        break;
    }
}

// What counts when it starts
#define MAIA_SETTER(Type, name, member)                                                                                \
    void Job::name(Type value)                                                                                         \
    {                                                                                                                  \
        if (member == value)                                                                                           \
            return;                                                                                                    \
        member = value;                                                                                                \
        Q_EMIT changed();                                                                                              \
    }

MAIA_SETTER(const QString &, setAppName, m_appName)
MAIA_SETTER(const QString &, setDesktopEntry, m_desktopEntry)
MAIA_SETTER(const QString &, setIconName, m_iconName)
MAIA_SETTER(bool, setKillable, m_killable)
MAIA_SETTER(bool, setSuspendable, m_suspendable)
MAIA_SETTER(bool, setImmediate, m_immediate)
MAIA_SETTER(bool, setTransient, m_transient)

#undef MAIA_SETTER

// The progress: to the service while it runs
#define MAIA_PROGRESS_SETTER(Type, name, member)                                                                       \
    void Job::name(Type value)                                                                                         \
    {                                                                                                                  \
        if (member == value)                                                                                           \
            return;                                                                                                    \
        member = value;                                                                                                \
        progressChanged();                                                                                             \
    }

MAIA_PROGRESS_SETTER(const QString &, setTitle, m_title)
MAIA_PROGRESS_SETTER(const QString &, setInfoMessage, m_infoMessage)
MAIA_PROGRESS_SETTER(int, setPercent, m_percent)
MAIA_PROGRESS_SETTER(qint64, setProcessedBytes, m_processedBytes)
MAIA_PROGRESS_SETTER(qint64, setTotalBytes, m_totalBytes)
MAIA_PROGRESS_SETTER(qint64, setProcessedFiles, m_processedFiles)
MAIA_PROGRESS_SETTER(qint64, setTotalFiles, m_totalFiles)
MAIA_PROGRESS_SETTER(qint64, setProcessedDirectories, m_processedDirectories)
MAIA_PROGRESS_SETTER(qint64, setTotalDirectories, m_totalDirectories)
MAIA_PROGRESS_SETTER(qint64, setProcessedItems, m_processedItems)
MAIA_PROGRESS_SETTER(qint64, setTotalItems, m_totalItems)
MAIA_PROGRESS_SETTER(qint64, setSpeed, m_speed)
MAIA_PROGRESS_SETTER(const QVariantList &, setFields, m_fields)
MAIA_PROGRESS_SETTER(const QUrl &, setDestination, m_destination)
MAIA_PROGRESS_SETTER(bool, setSuspended, m_suspended)

#undef MAIA_PROGRESS_SETTER

} // namespace MaiaNotifications
