#pragma once

// The wire protocol of CrossProcessState: frames on a Unix socket between the host process and the
// participants. Private to the module (both ends are this library), so it may change with Maia;
// kVersion guards against a participant of another build.
//
//   frame    = quint32 length (big endian) + payload, at most kMaxFrame bytes
//   payload  = QDataStream (Qt_6_0): quint8 kind, then the fields of the kind
//
//   participant → host                      host → participant
//   Hello    version                        Welcome   version, the participant's id
//   Join     category, entries              Snapshot  category, entries (all the host knows)
//   Set      category, key, value, seq,     Changed   category, key, value, origin id, seq,
//            revision                                 revision
//   Event    category, name, args           Event     category, name, args
//
// An entry is key, value and revision (0: still the declared default, then one more with every
// change): when a new host collects the state, the newest value of each key wins. A participant's
// Set comes back to it as Changed with its own id and seq: that is how it knows the
// host has it (see Link, "pending writes").

#include <QByteArray>
#include <QDataStream>
#include <QList>
#include <QString>
#include <QVariant>

#include <optional>

namespace MaiaCrossProcessState::Protocol {

constexpr quint32 kVersion = 2;
// A frame larger than this is a broken or hostile peer: the connection is closed
constexpr quint32 kMaxFrame = 4 * 1024 * 1024;

enum class Kind : quint8 {
    Hello = 1,
    Welcome,
    Join,
    Snapshot,
    Set,
    Changed,
    Event,
};

struct Entry {
    QString key;
    QVariant value;
    quint64 revision = 0;
};

// The payload with its length in front
QByteArray frame(const QByteArray &payload);

// Collects the bytes of a socket and hands out complete frames
class FrameReader
{
public:
    void append(const QByteArray &bytes) { m_buffer.append(bytes); }
    // The next complete payload; nullopt when more bytes are needed. *broken: a frame larger than
    // kMaxFrame (the connection should go)
    std::optional<QByteArray> next(bool *broken);

private:
    QByteArray m_buffer;
    qsizetype m_offset = 0;
};

QDataStream &operator<<(QDataStream &out, const Entry &entry);
QDataStream &operator>>(QDataStream &in, Entry &entry);

// Every payload is read and written with this stream version
constexpr QDataStream::Version kStreamVersion = QDataStream::Qt_6_0;

} // namespace MaiaCrossProcessState::Protocol
