#include "Protocol.h"

#include <QtEndian>

namespace MaiaCrossProcessState::Protocol {

QByteArray frame(const QByteArray &payload)
{
    QByteArray bytes;
    bytes.resize(4);
    qToBigEndian<quint32>(quint32(payload.size()), bytes.data());
    bytes.append(payload);
    return bytes;
}

std::optional<QByteArray> FrameReader::next(bool *broken)
{
    *broken = false;
    const qsizetype available = m_buffer.size() - m_offset;
    if (available < 4)
        return std::nullopt;
    const quint32 length = qFromBigEndian<quint32>(m_buffer.constData() + m_offset);
    if (length > kMaxFrame) {
        *broken = true;
        return std::nullopt;
    }
    if (available < 4 + qsizetype(length))
        return std::nullopt;
    QByteArray payload = m_buffer.mid(m_offset + 4, length);
    m_offset += 4 + length;
    // Drop what was read once it is the larger part (no copying per frame)
    if (m_offset == m_buffer.size()) {
        m_buffer.clear();
        m_offset = 0;
    } else if (m_offset > 64 * 1024 && m_offset > m_buffer.size() / 2) {
        m_buffer.remove(0, m_offset);
        m_offset = 0;
    }
    return payload;
}

QDataStream &operator<<(QDataStream &out, const Entry &entry)
{
    return out << entry.key << entry.value << entry.changed;
}

QDataStream &operator>>(QDataStream &in, Entry &entry)
{
    return in >> entry.key >> entry.value >> entry.changed;
}

} // namespace MaiaCrossProcessState::Protocol
