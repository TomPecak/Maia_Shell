#include "Link.h"

#include "CrossProcessState.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJSValue>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLoggingCategory>
#include <QSocketNotifier>
#include <QTimer>

#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cerrno>
#include <memory>
#include <utility>

Q_LOGGING_CATEGORY(lcCrossProcessState, "maia.crossprocessstate")

namespace MaiaCrossProcessState {

using namespace Protocol;

namespace {

Link *s_instance = nullptr;

// The identity of a socket file (inode and change time): a new host's socket is a new file
qint64 fileIdentity(const QString &path)
{
    struct stat info {};
    if (::stat(QFile::encodeName(path).constData(), &info) != 0)
        return -1;
    return qint64(info.st_ino) * 1000003 ^ (qint64(info.st_ctim.tv_sec) * 1000000000 + info.st_ctim.tv_nsec);
}

} // namespace

Link::Link(const QString &socketPath, QObject *parent)
    : QObject(parent)
    , m_path(socketPath)
{
    // Private to the user, as the other sockets of Maia
    const QString dir = QFileInfo(m_path).absolutePath();
    if (!QFileInfo::exists(dir) && QDir().mkpath(dir))
        QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
}

Link::~Link()
{
    if (s_instance == this)
        s_instance = nullptr;
    // What was changed last still goes out (as far as the socket takes it without waiting)
    flush();
    if (m_socket)
        m_socket->flush();
    for (Peer *peer : std::as_const(m_peers))
        peer->socket->flush();
    stopWatchingHolder();
    // In this order: its socket file goes while it still holds the lock (a successor's must never
    // be removed), then the lock, and only then do the participants hear the end and elect
    delete m_server;
    m_server = nullptr;
    releaseLock();
    for (Peer *peer : std::as_const(m_peers)) {
        peer->socket->disconnect(this);
        delete peer->socket;
        delete peer;
    }
    m_peers.clear();
}

Link *Link::instance()
{
    if (!s_instance)
        s_instance = new Link(defaultSocketPath(), QCoreApplication::instance());
    return s_instance;
}

QString Link::defaultSocketPath()
{
    const QString given = qEnvironmentVariable("MAIA_CROSS_PROCESS_STATE_SOCKET");
    if (!given.isEmpty())
        return given;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    // WAYLAND_DISPLAY may be an absolute path
    QString display = qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"));
    display = display.section(QLatin1Char('/'), -1);
    return runtime + QStringLiteral("/maia/cross-process-state-") + display + QStringLiteral(".sock");
}

bool Link::isSynced(const QString &category) const
{
    return isHost() || m_synced.contains(category);
}

QVariant Link::wireValue(const QVariant &value)
{
    if (!value.isValid())
        return value;
    if (value.metaType() == QMetaType::fromType<QJSValue>())
        return wireValue(value.value<QJSValue>().toVariant(QJSValue::ConvertJSObjects));
    switch (value.typeId()) {
    case QMetaType::QVariantList: {
        QVariantList list = value.toList();
        for (QVariant &item : list)
            item = wireValue(item);
        return list;
    }
    case QMetaType::QVariantMap:
    case QMetaType::QVariantHash: {
        QVariantMap map = value.toMap();
        for (QVariant &item : map)
            item = wireValue(item);
        return map;
    }
    default:
        break;
    }
    if (!value.metaType().hasRegisteredDataStreamOperators()) {
        qCWarning(lcCrossProcessState) << "a value of type" << value.metaType().name() << "cannot be shared";
        return {};
    }
    return value;
}

// --- Objects ---

void Link::attach(CrossProcessState *object, const QString &category, const QVariantHash &declared)
{
    auto &values = m_values[category];
    QList<QPair<QString, QVariant>> known;
    bool newKeys = false;
    for (auto it = declared.cbegin(); it != declared.cend(); ++it) {
        const auto found = values.constFind(it.key());
        if (found == values.cend()) {
            values.insert(it.key(), {it.value(), 0});
            newKeys = true;
        } else {
            known.append({it.key(), found->value});
        }
    }
    m_objects[category].append(object);
    // What this process already knows (another object, the host) wins over the declaration
    for (const auto &[key, value] : std::as_const(known))
        object->applyValue(key, value);

    if (!isHost()) {
        // Once per category and connection: another object of a joined category needs the host
        // only for keys this process did not know (a Repeater of fifty delegates is one join)
        if (m_welcomed && (newKeys || !m_joined.contains(category)))
            join(category);
        else if (!m_welcomed && !m_socket && !m_holderWatch)
            findHost();
    }
    object->setSynced(isSynced(category));
}

void Link::detach(CrossProcessState *object, const QString &category)
{
    auto it = m_objects.find(category);
    if (it == m_objects.end())
        return;
    it->removeIf([object](const QPointer<CrossProcessState> &o) { return o.isNull() || o == object; });
}

void Link::changedLocally(CrossProcessState *object, const QString &category, const QString &key, const QVariant &value)
{
    Entry &entry = m_values[category][key];
    if (entry.value == value && entry.revision > 0)
        return;
    entry.value = value;
    const quint64 revision = ++entry.revision;
    // Queued first: a handler that changes something else in turn is sent after this
    if (isHost()) {
        queue({Kind::Changed, category, key, value, {}, 0, 0, 0, revision});
    } else if (m_welcomed) {
        const quint64 seq = m_nextSeq++;
        m_pending.insert({category, key}, seq);
        queue({Kind::Set, category, key, value, {}, 0, seq, 0, revision});
    }
    // Without a connection: kept here with its revision, it goes to the host with the next Join
    applyToObjects(category, key, value, object);
}

void Link::emittedLocally(CrossProcessState *object, const QString &category, const QString &name, const QVariantList &args)
{
    deliverEvent(category, name, args, object);
    // An event is a moment: without a host it reaches this process only
    if (isHost() || m_welcomed)
        queue({Kind::Event, category, name, {}, args, 0, 0, 0, 0});
}

// --- Both roles ---

void Link::applyToObjects(const QString &category, const QString &key, const QVariant &value, CrossProcessState *except)
{
    // A copy: a handler may create or destroy objects meanwhile
    const auto objects = m_objects.value(category);
    for (const auto &object : objects) {
        if (object && object != except)
            object->applyValue(key, value);
    }
}

void Link::deliverEvent(const QString &category, const QString &name, const QVariantList &args, CrossProcessState *except)
{
    const auto objects = m_objects.value(category);
    for (const auto &object : objects) {
        if (object && object != except)
            object->applyEvent(name, args);
    }
}

void Link::setSynced(const QString &category, bool synced)
{
    if (synced)
        m_synced.insert(category);
    else
        m_synced.remove(category);
    const auto objects = m_objects.value(category);
    for (const auto &object : objects) {
        if (object)
            object->setSynced(isSynced(category));
    }
}

void Link::queue(Outgoing message)
{
    if (message.kind == Kind::Set || (message.kind == Kind::Changed && message.origin == 0)) {
        // A burst of changes of one key leaves as its last value. Only into the last message of
        // that key and only when it is of the same kind: a host's own change must not jump over a
        // participant's change it came after (the participant waits for its own back)
        const QPair<QString, QString> key{message.category, message.key};
        const auto found = m_queuedSets.constFind(key);
        if (found != m_queuedSets.cend()) {
            Outgoing &queued = m_outgoing[*found];
            if (queued.kind == message.kind && queued.origin == message.origin) {
                queued.value = message.value;
                queued.seq = message.seq;
                queued.revision = message.revision;
                return;
            }
        }
        m_queuedSets.insert(key, m_outgoing.size());
    } else if (message.kind == Kind::Changed) {
        m_queuedSets.insert({message.category, message.key}, m_outgoing.size());
    }
    m_outgoing.append(std::move(message));
    scheduleFlush();
}

void Link::scheduleFlush()
{
    if (m_flushQueued)
        return;
    m_flushQueued = true;
    // At the end of this turn of the event loop: everything changed meanwhile is one write
    QMetaObject::invokeMethod(this, &Link::flush, Qt::QueuedConnection);
}

void Link::flush()
{
    m_flushQueued = false;
    const QList<Outgoing> outgoing = std::exchange(m_outgoing, {});
    m_queuedSets.clear();
    if (outgoing.isEmpty())
        return;
    if (isHost()) {
        QHash<Peer *, QByteArray> batches;
        for (const Outgoing &message : outgoing) {
            const QByteArray bytes = frame(encode(message));
            for (Peer *peer : std::as_const(m_peers)) {
                if (peer->welcomed && peer->id != message.except && peer->categories.contains(message.category))
                    batches[peer].append(bytes);
            }
        }
        for (auto it = batches.cbegin(); it != batches.cend(); ++it)
            it.key()->socket->write(it.value());
    } else if (m_socket && m_welcomed) {
        QByteArray bytes;
        for (const Outgoing &message : outgoing)
            bytes.append(frame(encode(message)));
        m_socket->write(bytes);
    }
}

QByteArray Link::encode(const Outgoing &message) const
{
    QByteArray payload;
    QDataStream out(&payload, QIODevice::WriteOnly);
    out.setVersion(kStreamVersion);
    out << quint8(message.kind);
    switch (message.kind) {
    case Kind::Set:
        out << message.category << message.key << message.value << message.seq << message.revision;
        break;
    case Kind::Changed:
        out << message.category << message.key << message.value << message.origin << message.seq << message.revision;
        break;
    case Kind::Event:
        out << message.category << message.key << message.args << message.origin;
        break;
    default:
        break;
    }
    return payload;
}

QByteArray Link::encodeEntries(Kind kind, const QString &category) const
{
    QList<Protocol::Entry> entries;
    const auto values = m_values.value(category);
    entries.reserve(values.size());
    for (auto it = values.cbegin(); it != values.cend(); ++it)
        entries.append({it.key(), it->value, it->revision});
    QByteArray payload;
    QDataStream out(&payload, QIODevice::WriteOnly);
    out.setVersion(kStreamVersion);
    out << quint8(kind) << category << entries;
    return frame(payload);
}

// --- The election ---

void Link::findHost()
{
    if (electHost())
        return;
    // Before looking at the socket: a host that appears from now on is an event
    watchForHost();
    if (m_socket)
        return;
    const qint64 identity = fileIdentity(m_path);
    if (identity != -1 && identity != m_failedSocket)
        QMetaObject::invokeMethod(this, &Link::connectToHost, Qt::QueuedConnection);
}

bool Link::electHost()
{
    if (isHost())
        return true;
    stopWatchingHolder();
    int retry = 5;
    for (int attempt = 0; attempt < 3; ++attempt) {
        if (takeLock()) {
            if (becomeHost())
                return true;
            releaseLock();
            return false;
        }
        if (m_lockFd < 0)
            return false; // no lock file (warned): it can still take part in a host that is there
        const qint64 holder = lockHolder();
        if (holder <= 0)
            break;
        const int pidfd = int(::syscall(SYS_pidfd_open, pid_t(holder), 0));
        if (pidfd < 0) {
            // A kernel before 5.3 has no pidfd: the one case that has to look again now and then
            if (errno == ENOSYS) {
                retry = 1000;
                break;
            }
            continue; // it ended meanwhile: the lock is free, or has a new holder
        }
        // Looked at again now that its end cannot be missed
        if (takeLock()) {
            ::close(pidfd);
            if (becomeHost())
                return true;
            releaseLock();
            return false;
        }
        if (lockHolder() == holder) {
            watchHolder(pidfd);
            return false;
        }
        ::close(pidfd);
    }
    // The instant between a new holder taking the lock and writing its pid: the next moment knows
    if (!m_retryQueued) {
        m_retryQueued = true;
        QTimer::singleShot(retry, this, [this] {
            m_retryQueued = false;
            if (!m_holderWatch)
                findHost();
        });
    }
    return false;
}

bool Link::takeLock()
{
    if (m_lockFd < 0) {
        // CLOEXEC: the programs this process starts must not keep the lock alive
        m_lockFd = ::open(QFile::encodeName(m_path + QStringLiteral(".lock")).constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        if (m_lockFd < 0) {
            qCWarning(lcCrossProcessState) << "cannot open the lock of" << m_path << ":" << qt_error_string(errno);
            return false;
        }
    }
    if (::flock(m_lockFd, LOCK_EX | LOCK_NB) != 0)
        return false;
    // Who has it, for those who wait for its end
    const QByteArray pid = QByteArray::number(qint64(::getpid()));
    if (::ftruncate(m_lockFd, 0) != 0 || ::pwrite(m_lockFd, pid.constData(), size_t(pid.size()), 0) != pid.size())
        qCWarning(lcCrossProcessState) << "cannot write to the lock of" << m_path;
    return true;
}

void Link::releaseLock()
{
    if (m_lockFd >= 0) {
        ::close(m_lockFd);
        m_lockFd = -1;
    }
}

qint64 Link::lockHolder() const
{
    char text[32];
    const ssize_t size = ::pread(m_lockFd, text, sizeof text - 1, 0);
    return size > 0 ? QByteArray(text, size).toLongLong() : 0;
}

void Link::watchHolder(int pidfd)
{
    m_holderFd = pidfd;
    m_holderWatch = new QSocketNotifier(pidfd, QSocketNotifier::Read, this);
    connect(m_holderWatch, &QSocketNotifier::activated, this, [this] {
        stopWatchingHolder();
        findHost();
    });
}

void Link::stopWatchingHolder()
{
    if (m_holderWatch) {
        m_holderWatch->setEnabled(false);
        m_holderWatch->deleteLater();
        m_holderWatch = nullptr;
    }
    if (m_holderFd >= 0) {
        ::close(m_holderFd);
        m_holderFd = -1;
    }
}

// --- Host ---

bool Link::becomeHost()
{
    if (m_server)
        return true;
    // A participant until now: its connection goes, its values stay (they are the session's)
    if (m_socket) {
        m_socket->disconnect(this);
        m_socket->abort();
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    m_reader = {};
    m_welcomed = false;
    m_id = 0;
    m_pending.clear();
    m_joined.clear();
    m_outgoing.clear();
    m_queuedSets.clear();
    // A socket file left by a host that crashed: ours now (the lock says nobody serves it)
    QLocalServer::removeServer(m_path);
    auto server = std::make_unique<QLocalServer>(this);
    server->setSocketOptions(QLocalServer::UserAccessOption);
    connect(server.get(), &QLocalServer::newConnection, this, &Link::acceptPeers);
    if (!server->listen(m_path)) {
        qCWarning(lcCrossProcessState) << "cannot host" << m_path << ":" << server->errorString();
        return false;
    }
    m_server = server.release();
    const auto categories = m_objects.keys();
    for (const QString &category : categories)
        setSynced(category, true);
    return true;
}

void Link::acceptPeers()
{
    while (QLocalSocket *socket = m_server->nextPendingConnection()) {
        // Not a child of the server: at the end the server goes first (see ~Link)
        socket->setParent(this);
        auto *peer = new Peer;
        peer->socket = socket;
        peer->id = m_nextPeerId++;
        m_peers.append(peer);
        connect(socket, &QLocalSocket::readyRead, this, [this, peer] { readPeer(peer); });
        connect(socket, &QLocalSocket::disconnected, this, [this, peer] { dropPeer(peer); });
    }
}

void Link::readPeer(Peer *peer)
{
    peer->reader.append(peer->socket->readAll());
    for (;;) {
        bool broken = false;
        const auto payload = peer->reader.next(&broken);
        if (broken) {
            qCWarning(lcCrossProcessState) << "a participant sent a frame too large; it is disconnected";
            dropPeer(peer);
            return;
        }
        if (!payload)
            return;
        // The peer may be dropped by its message (a wrong version)
        const quint32 id = peer->id;
        handlePeerMessage(peer, *payload);
        if (!std::any_of(m_peers.cbegin(), m_peers.cend(), [id](const Peer *p) { return p->id == id; }))
            return;
    }
}

void Link::handlePeerMessage(Peer *peer, const QByteArray &payload)
{
    QDataStream in(payload);
    in.setVersion(kStreamVersion);
    quint8 kind = 0;
    in >> kind;
    switch (Kind(kind)) {
    case Kind::Hello: {
        quint32 version = 0;
        in >> version;
        if (version != kVersion) {
            qCWarning(lcCrossProcessState) << "a participant speaks version" << version << "instead of" << kVersion;
            dropPeer(peer);
            return;
        }
        peer->welcomed = true;
        QByteArray reply;
        QDataStream out(&reply, QIODevice::WriteOnly);
        out.setVersion(kStreamVersion);
        out << quint8(Kind::Welcome) << kVersion << peer->id;
        peer->socket->write(frame(reply));
        return;
    }
    case Kind::Join: {
        QString category;
        QList<Protocol::Entry> entries;
        in >> category >> entries;
        if (in.status() != QDataStream::Ok)
            break;
        // What is queued goes first: the snapshot below already has it
        flush();
        peer->categories.insert(category);
        for (const Protocol::Entry &entry : std::as_const(entries)) {
            auto &values = m_values[category];
            const auto found = values.constFind(entry.key);
            // The newest value of each key: a new host collects the session's state
            if (found != values.cend() && entry.revision <= found->revision)
                continue;
            values[entry.key] = {entry.value, entry.revision};
            queue({Kind::Changed, category, entry.key, entry.value, {}, peer->id, 0, peer->id, entry.revision});
            applyToObjects(category, entry.key, entry.value);
        }
        peer->socket->write(encodeEntries(Kind::Snapshot, category));
        return;
    }
    case Kind::Set: {
        QString category, key;
        QVariant value;
        quint64 seq = 0, revision = 0;
        in >> category >> key >> value >> seq >> revision;
        if (in.status() != QDataStream::Ok)
            break;
        peer->categories.insert(category);
        Entry &entry = m_values[category][key];
        entry.value = value;
        entry.revision = qMax(entry.revision + 1, revision);
        // To everyone in the category, the sender included (it waits for its own back)
        queue({Kind::Changed, category, key, value, {}, peer->id, seq, 0, entry.revision});
        applyToObjects(category, key, value);
        return;
    }
    case Kind::Event: {
        QString category, name;
        QVariantList args;
        quint32 origin = 0;
        in >> category >> name >> args >> origin;
        if (in.status() != QDataStream::Ok)
            break;
        deliverEvent(category, name, args);
        queue({Kind::Event, category, name, {}, args, peer->id, 0, peer->id, 0});
        return;
    }
    default:
        break;
    }
    qCWarning(lcCrossProcessState) << "a participant sent a message that cannot be read; it is disconnected";
    dropPeer(peer);
}

void Link::dropPeer(Peer *peer)
{
    if (!m_peers.removeOne(peer))
        return;
    peer->socket->disconnect(this);
    peer->socket->abort();
    peer->socket->deleteLater();
    delete peer;
}

// --- Participant ---

void Link::connectToHost()
{
    if (m_socket || isHost())
        return;
    // Known before the attempt: a socket that replaces this one meanwhile is a new one to try
    m_triedSocket = fileIdentity(m_path);
    if (m_triedSocket == -1)
        return;
    m_socket = new QLocalSocket(this);
    connect(m_socket, &QLocalSocket::connected, this, &Link::onConnected);
    connect(m_socket, &QLocalSocket::readyRead, this, &Link::readHost);
    connect(m_socket, &QLocalSocket::disconnected, this, &Link::lostHost);
    connect(m_socket, &QLocalSocket::errorOccurred, this, &Link::lostHost);
    // Asynchronous: the answer comes as connected() or errorOccurred()
    m_socket->connectToServer(m_path);
}

void Link::watchForHost()
{
    if (m_watcher)
        return;
    m_watcher = new QFileSystemWatcher(this);
    // inotify: a new host's socket appearing is an event, nothing is polled
    m_watcher->addPath(QFileInfo(m_path).absolutePath());
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        if (m_socket || isHost())
            return;
        const qint64 identity = fileIdentity(m_path);
        // No socket, or the same one that did not answer: nothing to try
        if (identity != -1 && identity != m_failedSocket)
            connectToHost();
    });
}

void Link::onConnected()
{
    QByteArray hello;
    QDataStream out(&hello, QIODevice::WriteOnly);
    out.setVersion(kStreamVersion);
    out << quint8(Kind::Hello) << kVersion;
    m_socket->write(frame(hello));
}

void Link::readHost()
{
    if (!m_socket)
        return;
    m_reader.append(m_socket->readAll());
    while (m_socket) {
        bool broken = false;
        const auto payload = m_reader.next(&broken);
        if (broken) {
            qCWarning(lcCrossProcessState) << "the host sent a frame too large";
            lostHost();
            return;
        }
        if (!payload)
            return;
        handleHostMessage(*payload);
    }
}

void Link::handleHostMessage(const QByteArray &payload)
{
    QDataStream in(payload);
    in.setVersion(kStreamVersion);
    quint8 kind = 0;
    in >> kind;
    switch (Kind(kind)) {
    case Kind::Welcome: {
        quint32 version = 0, id = 0;
        in >> version >> id;
        if (version != kVersion) {
            qCWarning(lcCrossProcessState) << "the host speaks version" << version << "instead of" << kVersion;
            lostHost();
            return;
        }
        m_welcomed = true;
        m_id = id;
        m_failedSocket = -1;
        const auto categories = m_objects.keys();
        for (const QString &category : categories)
            join(category);
        return;
    }
    case Kind::Snapshot: {
        QString category;
        QList<Protocol::Entry> entries;
        in >> category >> entries;
        if (in.status() != QDataStream::Ok)
            break;
        for (const Protocol::Entry &entry : std::as_const(entries)) {
            // Its own change is on its way: that one is the newer value
            if (m_pending.contains({category, entry.key}))
                continue;
            Entry &current = m_values[category][entry.key];
            const bool differs = current.value != entry.value;
            current = {entry.value, entry.revision};
            if (differs)
                applyToObjects(category, entry.key, entry.value);
        }
        setSynced(category, true);
        return;
    }
    case Kind::Changed: {
        QString category, key;
        QVariant value;
        quint32 origin = 0;
        quint64 seq = 0, revision = 0;
        in >> category >> key >> value >> origin >> seq >> revision;
        if (in.status() != QDataStream::Ok)
            break;
        const QPair<QString, QString> pendingKey{category, key};
        if (origin == m_id && seq != 0) {
            // Its own change, back in the host's order: the host has it
            Entry &own = m_values[category][key];
            own.revision = qMax(own.revision, revision);
            if (m_pending.value(pendingKey) == seq)
                m_pending.remove(pendingKey);
            return;
        }
        if (m_pending.contains(pendingKey))
            return;
        Entry &current = m_values[category][key];
        const bool differs = current.value != value;
        current = {value, revision};
        if (differs)
            applyToObjects(category, key, value);
        return;
    }
    case Kind::Event: {
        QString category, name;
        QVariantList args;
        quint32 origin = 0;
        in >> category >> name >> args >> origin;
        if (in.status() != QDataStream::Ok)
            break;
        deliverEvent(category, name, args);
        return;
    }
    default:
        break;
    }
    qCWarning(lcCrossProcessState) << "the host sent a message that cannot be read";
    lostHost();
}

void Link::lostHost()
{
    if (!m_socket)
        return;
    if (!m_welcomed)
        m_failedSocket = m_triedSocket;
    m_socket->disconnect(this);
    m_socket->abort();
    m_socket->deleteLater();
    m_socket = nullptr;
    m_reader = {};
    m_welcomed = false;
    m_id = 0;
    m_pending.clear();
    m_joined.clear();
    // What was not sent stays in m_values with its revision and goes with the next Join
    m_outgoing.clear();
    m_queuedSets.clear();
    const auto categories = m_synced;
    for (const QString &category : categories)
        setSynced(category, false);
    // Takes over, or waits for whoever does (or for the holder of the lock to end)
    findHost();
}

void Link::join(const QString &category)
{
    if (!m_socket || !m_welcomed)
        return;
    // Its queued changes first, in order
    flush();
    m_joined.insert(category);
    ++m_joinsSent;
    m_socket->write(encodeEntries(Kind::Join, category));
}

} // namespace MaiaCrossProcessState
