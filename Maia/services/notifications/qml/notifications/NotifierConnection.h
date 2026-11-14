#pragma once

// The connection of a process to the Notifier of the notification service (the senders' socket).
// One per process (instance()), shared by every Notification object.
//
// Notifications sent while the service is not there (the session is starting, the service
// restarts) wait and go out when it comes; at most kMaxWaiting, the oldest are dropped. When the
// connection ends, the service has lost its list (it keeps nothing on disk): every shown
// notification counts as closed (reason Other). Running jobs are started again, with their state
// of then, when the service is back.
//
// Socket: $MAIA_NOTIFICATIONS_SOCKET, or $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock

#include "Contract.h"
#include "ServiceLink.h"

#include <QHash>
#include <QList>
#include <QSet>

#include <map>
#include <mutex>
#include <vector>
#include <optional>

namespace MaiaNotifications {

class Job;
class Notification;

class NotifierConnection final : public ServiceLink
{
    Q_OBJECT

public:
    explicit NotifierConnection(const QString &socketPath, QObject *parent = nullptr);
    ~NotifierConnection() override;

    static NotifierConnection *instance();
    static QString defaultSocketPath();

    static constexpr int kMaxWaiting = 32;

    // A new notification of `object`; returns this process's number for it. What happens to it is
    // told to `object` alone (a direct call, not a signal every object would have to filter)
    int send(const RequestData &request, Notification *object);
    // Replaces the content of a sent notification
    void update(int local, const RequestData &request);
    void close(int local);
    // Its object is gone: the handle is dropped, the notification stays
    void release(int local);

    // A job of `object` (Job.start()); returns this process's number for it. Sent now, or when
    // the service comes (again), with the object's state of then
    int startJob(Job *object);
    void updateJob(int local, const JobProgressData &progress);
    // The end: "" done, else failed with the text
    void finishJob(int local, const QString &errorText);
    void cancelJob(int local);
    // Its object is gone while it runs: the handle is dropped, the service fails the job
    void releaseJob(int local);

    // What the user asks of a job (Job::onRequest)
    enum JobRequestKind { JobCancel, JobSuspend, JobResume };

protected:
    void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) override;
    void disconnected() override;

private:
    friend class SenderListener;
    friend class JobListenerImpl;

    void postSend(int local, const RequestData &request);
    void flushWaiting();
    // GUI thread: to the object of `local`, if it still exists and the notification is shown
    void deliverSent(int local, quint32 id);
    void deliverAction(int local, const QString &key, const QString &token);
    void deliverReply(int local, const QString &text, const QString &token);
    void deliverClosed(int local, int reason);
    void postStartJob(int local, const JobRequestData &request);
    void endJob(int local, std::optional<QString> errorText);

    // What the service tells, collected in the KJ thread and handed to the GUI thread together:
    // a flood of answers is one queued call, not one per notification
    struct Event {
        enum Kind { Sent, Action, Reply, Closed, JobStarted, JobAsked } kind;
        int local;
        quint32 id = 0;
        QString text;
        QString token;
        // Closed: the reason; JobAsked: a JobRequestKind
        int reason = 0;
    };
    void tell(Event event);
    void deliver();

    // GUI thread
    int m_nextLocal = 0;
    QList<QPair<int, RequestData>> m_waiting;
    QSet<int> m_active;
    QHash<int, Notification *> m_objects;
    // Running jobs
    QHash<int, Job *> m_jobs;

    std::mutex m_eventsMutex;
    std::vector<Event> m_events;

    // KJ thread
    std::optional<C::Notifier::Client> m_notifier;
    std::map<int, C::NotificationHandle::Client> m_handles;
    std::map<int, C::JobHandle::Client> m_jobHandles;
};

} // namespace MaiaNotifications
