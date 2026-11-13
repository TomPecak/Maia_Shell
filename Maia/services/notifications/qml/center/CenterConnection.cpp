#include "CenterConnection.h"

#include <QCoreApplication>
#include <QDebug>

namespace MaiaNotifications {

namespace {

CenterConnection *s_instance = nullptr;

// Logs a refused request: the shell has nothing to show for it (the notification was gone)
template<typename Response>
void logResult(const char *action, Response &&response)
{
    auto result = response.getResult();
    if (result.getError() != C::ErrorCode::NONE)
        qDebug() << "[Maia.Notifications.Center]" << action << "refused:" << toQString(result.getMessage());
}

} // namespace

// The service's calls (KJ thread): read into Qt values here, applied in the GUI thread
class ShellListener final : public C::CenterListener::Server
{
public:
    explicit ShellListener(CenterConnection *connection)
        : m_connection(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        auto s = context.getParams().getSnapshot();
        QList<NotificationData> list;
        auto notifications = s.getNotifications();
        list.reserve(notifications.size());
        for (auto n : notifications)
            list.append(readNotification(n));
        const DoNotDisturbData dnd = readDoNotDisturb(s.getDoNotDisturb());
        QList<JobData> jobs;
        for (auto j : s.getJobs())
            jobs.append(readJob(j));
        m_connection->toGui([c = m_connection, list = std::move(list), dnd, jobs = std::move(jobs)] { c->applySnapshot(list, dnd, jobs); });
        return kj::READY_NOW;
    }

    kj::Promise<void> changes(ChangesContext context) override
    {
        auto p = context.getParams();
        QList<NotificationData> changed;
        changed.reserve(p.getChanged().size());
        for (auto n : p.getChanged())
            changed.append(readNotification(n));
        QList<quint32> removed;
        for (auto id : p.getRemoved())
            removed.append(id);
        m_connection->toGui([c = m_connection, changed = std::move(changed), removed = std::move(removed)] {
            c->applyBatch(changed, removed);
        });
        return kj::READY_NOW;
    }

    kj::Promise<void> jobsChanged(JobsChangedContext context) override
    {
        auto p = context.getParams();
        QList<JobData> changed;
        for (auto j : p.getChanged())
            changed.append(readJob(j));
        QList<quint32> removed;
        for (auto id : p.getRemoved())
            removed.append(id);
        m_connection->toGui([c = m_connection, changed = std::move(changed), removed = std::move(removed)] { c->applyJobs(changed, removed); });
        return kj::READY_NOW;
    }

    kj::Promise<void> doNotDisturbChanged(DoNotDisturbChangedContext context) override
    {
        const DoNotDisturbData dnd = readDoNotDisturb(context.getParams().getDoNotDisturb());
        m_connection->toGui([c = m_connection, dnd] { c->applyDoNotDisturb(dnd); });
        return kj::READY_NOW;
    }

private:
    CenterConnection *m_connection;
};

CenterConnection::CenterConnection(const QString &socketPath, QObject *parent)
    : ServiceLink(socketPath, QStringLiteral("Maia.Notifications.Center"), parent)
{
    start();
}

CenterConnection::~CenterConnection()
{
    stop();
    if (s_instance == this)
        s_instance = nullptr;
}

CenterConnection *CenterConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new CenterConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString CenterConnection::defaultSocketPath()
{
    return socketPathFor("MAIA_NOTIFICATIONS_CENTER_SOCKET", QStringLiteral("notifications-center"));
}

const NotificationData *CenterConnection::find(quint32 id) const
{
    auto it = m_notifications.constFind(id);
    return it == m_notifications.constEnd() ? nullptr : &*it;
}

// --- KJ thread ---

void CenterConnection::connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks)
{
    m_center = bootstrap.castAs<C::NotificationCenter>();
    auto watch = m_center->watchRequest();
    watch.setListener(kj::heap<ShellListener>(this));
    auto watched = watch.send();
    // Kept for the whole connection: releasing it would stop the listener
    m_subscription = watched.getSubscription();
    tasks.add(watched.ignoreResult());
}

void CenterConnection::disconnected()
{
    m_subscription.reset();
    m_center.reset();
}

// --- GUI thread: the state ---

void CenterConnection::applySnapshot(const QList<NotificationData> &list, const DoNotDisturbData &dnd, const QList<JobData> &jobs)
{
    m_jobs.clear();
    for (const auto &job : jobs)
        m_jobs.insert(job.id, job);
    Q_EMIT jobsReset();
    m_notifications.clear();
    m_notifications.reserve(list.size());
    for (const auto &n : list)
        m_notifications.insert(n.id, n);
    Q_EMIT reset();
    applyDoNotDisturb(dnd);
}

void CenterConnection::applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed)
{
    for (quint32 id : removed)
        m_notifications.remove(id);
    for (const auto &n : changed)
        m_notifications.insert(n.id, n);
    Q_EMIT batch(changed, removed);
}

void CenterConnection::applyJobs(const QList<JobData> &changed, const QList<quint32> &removed)
{
    for (quint32 id : removed)
        m_jobs.remove(id);
    for (const auto &job : changed)
        m_jobs.insert(job.id, job);
    Q_EMIT jobsBatch(changed, removed);
}

void CenterConnection::applyDoNotDisturb(const DoNotDisturbData &dnd)
{
    if (m_doNotDisturb == dnd)
        return;
    m_doNotDisturb = dnd;
    Q_EMIT doNotDisturbChanged();
}

// --- Requests (GUI thread) ---

void CenterConnection::invokeAction(quint32 id, const QString &key, const QString &activationToken)
{
    post([this, id, key = key.toUtf8(), token = activationToken.toUtf8()](kj::TaskSet &tasks) {
        auto call = m_center->invokeActionRequest();
        call.setId(id);
        call.setKey(key.constData());
        call.setActivationToken(token.constData());
        tasks.add(call.send().then([](auto &&response) { logResult("invokeAction", response); }));
    });
}

void CenterConnection::reply(quint32 id, const QString &text, const QString &activationToken)
{
    post([this, id, text = text.toUtf8(), token = activationToken.toUtf8()](kj::TaskSet &tasks) {
        auto call = m_center->replyRequest();
        call.setId(id);
        call.setText(text.constData());
        call.setActivationToken(token.constData());
        tasks.add(call.send().then([](auto &&response) { logResult("reply", response); }));
    });
}

void CenterConnection::dismiss(quint32 id)
{
    post([this, id](kj::TaskSet &tasks) {
        auto call = m_center->dismissRequest();
        call.setId(id);
        tasks.add(call.send().then([](auto &&response) { logResult("dismiss", response); }));
    });
}

void CenterConnection::expire(quint32 id)
{
    post([this, id](kj::TaskSet &tasks) {
        auto call = m_center->expireRequest();
        call.setId(id);
        tasks.add(call.send().then([](auto &&response) { logResult("expire", response); }));
    });
}

void CenterConnection::dismissAll()
{
    post([this](kj::TaskSet &tasks) { tasks.add(m_center->dismissAllRequest().send().ignoreResult()); });
}

void CenterConnection::setDoNotDisturb(bool enabled, qint64 until)
{
    post([this, enabled, until](kj::TaskSet &tasks) {
        auto call = m_center->setDoNotDisturbRequest();
        call.setEnabled(enabled);
        call.setUntil(until);
        tasks.add(call.send().ignoreResult());
    });
}

void CenterConnection::cancelJob(quint32 id)
{
    post([this, id](kj::TaskSet &tasks) {
        auto call = m_center->cancelJobRequest();
        call.setId(id);
        tasks.add(call.send().then([](auto &&response) { logResult("cancelJob", response); }));
    });
}

void CenterConnection::suspendJob(quint32 id, bool suspended)
{
    post([this, id, suspended](kj::TaskSet &tasks) {
        auto call = m_center->suspendJobRequest();
        call.setId(id);
        call.setSuspended(suspended);
        tasks.add(call.send().then([](auto &&response) { logResult("suspendJob", response); }));
    });
}

void CenterConnection::dismissJob(quint32 id)
{
    post([this, id](kj::TaskSet &tasks) {
        auto call = m_center->dismissJobRequest();
        call.setId(id);
        tasks.add(call.send().then([](auto &&response) { logResult("dismissJob", response); }));
    });
}

} // namespace MaiaNotifications
