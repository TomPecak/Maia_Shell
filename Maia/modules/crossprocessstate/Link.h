#pragma once

// Link: the one connection of a process to the shared state of its session, used by every
// CrossProcessState object of the process. It is either
//   - the host (a CrossProcessState object with host: true is in this process): it serves a
//     QLocalServer and keeps the authoritative values, or
//   - a participant: a QLocalSocket to the host.
// Objects of one category in one process see each other's changes at once, without the socket.
//
// Never blocking, never polling: sockets are asynchronous, nothing waits for bytes. A participant
// without a host watches the socket's directory (inotify through QFileSystemWatcher) and connects
// when a new host's socket appears. Changes made in one turn of the event loop leave as one write.
//
// A second process with host: true takes part while the first one hosts, and takes over when that
// one is gone (its lock is free then, or stale).
//
// Values: what QDataStream writes of a QVariant (bool, numbers, strings, url, color, date, lists and
// maps of these; JavaScript objects and arrays become maps and lists). Each value knows whether it
// was ever changed: when a host comes (back), a changed value of a participant wins over the host's
// declared default, so a restarted host gets the session's state back; between two changed values
// the host wins.
//
// Pending writes: a participant's change goes to the host and comes back to everyone, the
// participant included, in the host's order. Until its own change is back, a participant ignores
// other values of that key: two processes writing at once end with the same value everywhere, and
// none of them flickers through the other's value.
//
// Socket: $MAIA_CROSS_PROCESS_STATE_SOCKET, or
//         $XDG_RUNTIME_DIR/maia/cross-process-state-$WAYLAND_DISPLAY.sock (+ ".lock", the host's lock)

#include "Protocol.h"

#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QVariant>

class QFileSystemWatcher;
class QLocalServer;
class QLocalSocket;
class QLockFile;

namespace MaiaCrossProcessState {

class CrossProcessState;

class Link : public QObject
{
    Q_OBJECT

public:
    explicit Link(const QString &socketPath, QObject *parent = nullptr);
    ~Link() override;

    // The link of this process (created on first use, lives as long as the application)
    static Link *instance();
    static QString defaultSocketPath();

    QString socketPath() const { return m_path; }
    bool isHost() const { return m_server != nullptr; }
    bool isConnected() const { return m_welcomed; }
    // The category has the host's values (always on the host)
    bool isSynced(const QString &category) const;

    // An object is complete: its declared properties (with their values) and signals. The object
    // gets the values this process already knows of its keys.
    void attach(CrossProcessState *object, const QString &category, const QVariantHash &declared, bool host);
    void detach(CrossProcessState *object, const QString &category);

    // From an object: one of its properties changed, one of its signals was emitted
    void changedLocally(CrossProcessState *object, const QString &category, const QString &key, const QVariant &value);
    void emittedLocally(CrossProcessState *object, const QString &category, const QString &name, const QVariantList &args);

    // A value the way it travels: JavaScript values as maps and lists; invalid when it cannot
    static QVariant wireValue(const QVariant &value);

private:
    struct Entry {
        QVariant value;
        bool changed = false;
    };

    // A participant, as the host sees it
    struct Peer {
        QLocalSocket *socket = nullptr;
        quint32 id = 0;
        bool welcomed = false;
        QSet<QString> categories;
        Protocol::FrameReader reader;
    };

    // What waits for the end of the turn of the event loop
    struct Outgoing {
        Protocol::Kind kind;
        QString category;
        QString key;
        QVariant value;
        QVariantList args;
        quint32 origin = 0;
        quint64 seq = 0;
        // Host: a peer that does not get it (the sender of an event)
        quint32 except = 0;
    };

    // --- Both roles ---
    void store(const QString &category, const QString &key, const QVariant &value, bool changed);
    void applyToObjects(const QString &category, const QString &key, const QVariant &value, CrossProcessState *except = nullptr);
    void deliverEvent(const QString &category, const QString &name, const QVariantList &args, CrossProcessState *except = nullptr);
    void setSynced(const QString &category, bool synced);
    void queue(Outgoing message);
    void scheduleFlush();
    void flush();
    QByteArray encode(const Outgoing &message) const;
    QByteArray encodeEntries(Protocol::Kind kind, const QString &category) const;

    // --- Host ---
    bool becomeHost();
    void acceptPeers();
    void readPeer(Peer *peer);
    void handlePeerMessage(Peer *peer, const QByteArray &payload);
    void dropPeer(Peer *peer);

    // --- Participant ---
    void connectToHost();
    void watchForHost();
    void onConnected();
    void readHost();
    void handleHostMessage(const QByteArray &payload);
    void lostHost();
    void join(const QString &category);

    const QString m_path;
    // category → key → value: everything this process knows (the host: the authority)
    QHash<QString, QHash<QString, Entry>> m_values;
    QHash<QString, QList<QPointer<CrossProcessState>>> m_objects;
    QSet<QString> m_synced;

    QList<Outgoing> m_outgoing;
    // (category, key) → its Set in m_outgoing: a burst of changes of one key leaves as the last one
    QHash<QPair<QString, QString>, qsizetype> m_queuedSets;
    bool m_flushQueued = false;

    // Host
    QLocalServer *m_server = nullptr;
    QLockFile *m_lock = nullptr;
    QList<Peer *> m_peers;
    quint32 m_nextPeerId = 1;

    // An object of this process asked to host: when the host it lost the race to is gone, this
    // process takes over
    bool m_wantsHost = false;

    // Participant
    QLocalSocket *m_socket = nullptr;
    Protocol::FrameReader m_reader;
    bool m_welcomed = false;
    quint32 m_id = 0;
    quint64 m_nextSeq = 1;
    QHash<QPair<QString, QString>, quint64> m_pending;
    QFileSystemWatcher *m_watcher = nullptr;
    // The socket file of a host that did not answer: tried again only when it changes
    qint64 m_failedSocketTime = -1;
};

} // namespace MaiaCrossProcessState
