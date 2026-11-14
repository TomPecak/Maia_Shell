#include "NotifierConnection.h"

#include "Job.h"
#include "Notification.h"

#include <QCoreApplication>
#include <QDebug>

namespace MaiaNotifications {

namespace {
NotifierConnection *s_instance = nullptr;
}

// The service's calls about one notification (KJ thread), handed to the GUI thread in order
class SenderListener final : public C::NotifierListener::Server
{
public:
    SenderListener(NotifierConnection *connection, int local)
        : m_connection(connection)
        , m_local(local)
    {
    }

protected:
    kj::Promise<void> actionInvoked(ActionInvokedContext context) override
    {
        auto p = context.getParams();
        const QString key = toQString(p.getKey());
        const QString token = toQString(p.getActivationToken());
        m_connection->tell({NotifierConnection::Event::Action, m_local, 0, key, token});
        return kj::READY_NOW;
    }

    kj::Promise<void> replied(RepliedContext context) override
    {
        auto p = context.getParams();
        const QString text = toQString(p.getText());
        const QString token = toQString(p.getActivationToken());
        m_connection->tell({NotifierConnection::Event::Reply, m_local, 0, text, token});
        return kj::READY_NOW;
    }

    kj::Promise<void> closed(ClosedContext context) override
    {
        const int reason = int(context.getParams().getReason());
        m_connection->tell({NotifierConnection::Event::Closed, m_local, 0, {}, {}, reason});
        return kj::READY_NOW;
    }

private:
    NotifierConnection *m_connection;
    int m_local;
};

// What the user asks of one job (KJ thread), handed to the GUI thread in order
class JobListenerImpl final : public C::JobListener::Server
{
public:
    JobListenerImpl(NotifierConnection *connection, int local)
        : m_connection(connection)
        , m_local(local)
    {
    }

protected:
    kj::Promise<void> cancelRequested(CancelRequestedContext) override
    {
        return ask(NotifierConnection::JobCancel);
    }

    kj::Promise<void> suspendRequested(SuspendRequestedContext) override
    {
        return ask(NotifierConnection::JobSuspend);
    }

    kj::Promise<void> resumeRequested(ResumeRequestedContext) override
    {
        return ask(NotifierConnection::JobResume);
    }

private:
    kj::Promise<void> ask(int kind)
    {
        m_connection->tell({NotifierConnection::Event::JobAsked, m_local, 0, {}, {}, kind});
        return kj::READY_NOW;
    }

    NotifierConnection *m_connection;
    int m_local;
};

NotifierConnection::NotifierConnection(const QString &socketPath, QObject *parent)
    : ServiceLink(socketPath, QStringLiteral("Maia.Notifications"), parent)
{
    connect(this, &ServiceLink::connectedChanged, this, [this] {
        if (isConnected()) {
            flushWaiting();
            // Its jobs were lost with the service (or never sent): out now, as they are
            for (auto it = m_jobs.cbegin(); it != m_jobs.cend(); ++it)
                postStartJob(it.key(), it.value()->request());
        } else {
            // The service's list is gone with it
            const auto active = m_active;
            for (int local : active)
                deliverClosed(local, int(C::CloseReason::OTHER));
            for (Job *job : std::as_const(m_jobs))
                job->onLost();
        }
    });
    start();
}

NotifierConnection::~NotifierConnection()
{
    stop();
    if (s_instance == this)
        s_instance = nullptr;
}

NotifierConnection *NotifierConnection::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new NotifierConnection(defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

QString NotifierConnection::defaultSocketPath()
{
    return socketPathFor("MAIA_NOTIFICATIONS_SOCKET", QStringLiteral("notifications"));
}

void NotifierConnection::connected(capnp::Capability::Client bootstrap, kj::TaskSet &)
{
    m_notifier = bootstrap.castAs<C::Notifier>();
}

void NotifierConnection::disconnected()
{
    m_handles.clear();
    m_jobHandles.clear();
    m_notifier.reset();
}

int NotifierConnection::send(const RequestData &request, Notification *object)
{
    const int local = ++m_nextLocal;
    m_objects.insert(local, object);
    if (isConnected()) {
        postSend(local, request);
    } else {
        m_waiting.append({local, request});
        if (m_waiting.size() > kMaxWaiting)
            m_waiting.removeFirst();
    }
    return local;
}

void NotifierConnection::flushWaiting()
{
    const auto waiting = std::exchange(m_waiting, {});
    for (const auto &[local, request] : waiting)
        postSend(local, request);
}

void NotifierConnection::postSend(int local, const RequestData &request)
{
    m_active.insert(local);
    post([this, local, request](kj::TaskSet &tasks) {
        if (!m_notifier)
            return;
        auto call = m_notifier->notifyRequest();
        writeRequest(call.initNotification(), request);
        call.setListener(kj::heap<SenderListener>(this, local));
        auto promise = call.send();
        // Pipelined: update() and close() work before the answer
        m_handles.insert_or_assign(local, promise.getHandle());
        auto done = [this, local](auto &&response) {
            const quint32 id = response.getId();
            tell({Event::Sent, local, id});
        };
        tasks.add(promise.then(kj::cp(done)));
    });
}

void NotifierConnection::update(int local, const RequestData &request)
{
    for (auto &waiting : m_waiting) {
        if (waiting.first == local) {
            waiting.second = request;
            return;
        }
    }
    post([this, local, request](kj::TaskSet &tasks) {
        auto handle = m_handles.find(local);
        if (handle == m_handles.end())
            return;
        auto call = handle->second.updateRequest();
        writeRequest(call.initNotification(), request);
        auto done = [this, local](auto &&response) {
            if (response.getResult().getError() != C::ErrorCode::NONE) {
                // Closed meanwhile (by the user): the object may send it anew
                tell({Event::Closed, local, 0, {}, {}, int(C::CloseReason::OTHER)});
            }
        };
        tasks.add(call.send().then(kj::cp(done)));
    });
}

void NotifierConnection::close(int local)
{
    for (int i = 0; i < m_waiting.size(); ++i) {
        if (m_waiting[i].first == local) {
            m_waiting.removeAt(i);
            return;
        }
    }
    post([this, local](kj::TaskSet &tasks) {
        auto handle = m_handles.find(local);
        if (handle != m_handles.end())
            tasks.add(handle->second.closeRequest().send().ignoreResult());
    });
}

void NotifierConnection::release(int local)
{
    m_active.remove(local);
    m_objects.remove(local);
    for (int i = 0; i < m_waiting.size(); ++i) {
        if (m_waiting[i].first == local) {
            // Sent once it can be: a notification outlives its object
            return;
        }
    }
    post([this, local](kj::TaskSet &) { m_handles.erase(local); });
}

int NotifierConnection::startJob(Job *object)
{
    const int local = ++m_nextLocal;
    m_jobs.insert(local, object);
    if (isConnected())
        postStartJob(local, object->request());
    return local;
}

void NotifierConnection::postStartJob(int local, const JobRequestData &request)
{
    post([this, local, request](kj::TaskSet &tasks) {
        if (!m_notifier)
            return;
        auto call = m_notifier->startJobRequest();
        writeJobRequest(call.initJob(), request);
        call.setListener(kj::heap<JobListenerImpl>(this, local));
        auto promise = call.send();
        // Pipelined: updates and the end work before the answer
        m_jobHandles.insert_or_assign(local, promise.getHandle());
        auto done = [this, local](auto &&response) {
            tell({Event::JobStarted, local, response.getId(), {}, {}});
        };
        tasks.add(promise.then(kj::cp(done)));
    });
}

void NotifierConnection::updateJob(int local, const JobProgressData &progress)
{
    post([this, local, progress](kj::TaskSet &tasks) {
        auto handle = m_jobHandles.find(local);
        if (handle == m_jobHandles.end())
            return;
        auto call = handle->second.updateRequest();
        writeJobProgress(call.initProgress(), progress);
        tasks.add(call.send().ignoreResult());
    });
}

void NotifierConnection::finishJob(int local, const QString &errorText)
{
    endJob(local, errorText);
}

void NotifierConnection::cancelJob(int local)
{
    endJob(local, std::nullopt);
}

void NotifierConnection::endJob(int local, std::optional<QString> errorText)
{
    // Not sent yet (no service): nothing to end
    if (!m_jobs.remove(local))
        return;
    post([this, local, errorText](kj::TaskSet &tasks) {
        auto handle = m_jobHandles.find(local);
        if (handle == m_jobHandles.end())
            return;
        if (errorText) {
            auto call = handle->second.finishRequest();
            call.setErrorText(errorText->toUtf8().constData());
            tasks.add(call.send().ignoreResult());
        } else {
            tasks.add(handle->second.canceledRequest().send().ignoreResult());
        }
        // Dropped after the end: it no longer fails the job
        m_jobHandles.erase(handle);
    });
}

void NotifierConnection::releaseJob(int local)
{
    m_jobs.remove(local);
    post([this, local](kj::TaskSet &) { m_jobHandles.erase(local); });
}

void NotifierConnection::tell(Event event)
{
    bool first;
    {
        std::lock_guard lock(m_eventsMutex);
        first = m_events.empty();
        m_events.push_back(std::move(event));
    }
    if (first)
        toGui([this] { deliver(); });
}

void NotifierConnection::deliver()
{
    std::vector<Event> events;
    {
        std::lock_guard lock(m_eventsMutex);
        events.swap(m_events);
    }
    for (const Event &e : events) {
        switch (e.kind) {
        case Event::Sent:
            deliverSent(e.local, e.id);
            break;
        case Event::Action:
            deliverAction(e.local, e.text, e.token);
            break;
        case Event::Reply:
            deliverReply(e.local, e.text, e.token);
            break;
        case Event::Closed:
            deliverClosed(e.local, e.reason);
            break;
        case Event::JobStarted:
            if (Job *job = m_jobs.value(e.local))
                job->onStarted(e.id);
            break;
        case Event::JobAsked:
            if (Job *job = m_jobs.value(e.local))
                job->onRequest(e.reason);
            break;
        }
    }
}

void NotifierConnection::deliverSent(int local, quint32 id)
{
    if (Notification *object = m_objects.value(local))
        object->onSent(id);
}

void NotifierConnection::deliverAction(int local, const QString &key, const QString &token)
{
    if (Notification *object = m_objects.value(local))
        object->onActionInvoked(key, token);
}

void NotifierConnection::deliverReply(int local, const QString &text, const QString &token)
{
    if (Notification *object = m_objects.value(local))
        object->onReplied(text, token);
}

void NotifierConnection::deliverClosed(int local, int reason)
{
    if (!m_active.remove(local))
        return;
    // The object may send it anew: that is a new number
    if (Notification *object = m_objects.take(local))
        object->onClosed(reason);
}

} // namespace MaiaNotifications
