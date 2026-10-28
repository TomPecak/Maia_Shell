#include "WindowSource.h"

#include <QDataStream>
#include <QSet>

namespace MaiaWindows {

WindowSource::WindowSource(QObject *parent)
    : QObject(parent)
{
}

int WindowSource::indexOf(const QString &id) const
{
    // A few dozen windows at most: a linear search is faster than keeping an index up to date
    for (int i = 0; i < m_windows.size(); ++i) {
        if (m_windows.at(i).id == id)
            return i;
    }
    return -1;
}

const WindowInfo *WindowSource::window(const QString &id) const
{
    const int i = indexOf(id);
    return i >= 0 ? &m_windows.at(i) : nullptr;
}

void WindowSource::applySnapshot(const QList<WindowInfo> &windows)
{
    QSet<QString> present;
    for (const WindowInfo &window : windows)
        present.insert(window.id);
    // Copy of the ids: remove() changes m_windows
    QStringList gone;
    for (const WindowInfo &window : std::as_const(m_windows)) {
        if (!present.contains(window.id))
            gone.append(window.id);
    }
    for (const QString &id : std::as_const(gone))
        remove(id);
    for (const WindowInfo &window : windows)
        upsert(window);
}

void WindowSource::upsert(const WindowInfo &window)
{
    const int i = indexOf(window.id);
    if (i < 0) {
        m_windows.append(window);
        Q_EMIT windowAdded(window);
        return;
    }
    if (m_windows.at(i) == window)
        return;
    const WindowInfo before = m_windows.at(i);
    m_windows[i] = window;
    Q_EMIT windowChanged(before, window);
}

void WindowSource::remove(const QString &id)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    const WindowInfo window = m_windows.takeAt(i);
    m_icons.remove(id);
    Q_EMIT windowRemoved(window);
}

void WindowSource::setConnected(bool connected, quint32 capabilities)
{
    if (connected)
        m_capabilities = capabilities;
    if (m_connected == connected)
        return;
    m_connected = connected;
    // Icons being fetched over the old connection will not come
    for (CachedIcon &icon : m_icons)
        icon.pending = false;
    Q_EMIT connectedChanged();
}

QIcon WindowSource::bitmapIcon(const WindowInfo &window)
{
    if (window.iconSerial == 0)
        return {};
    CachedIcon &cached = m_icons[window.id];
    if (cached.serial == window.iconSerial)
        return cached.icon;
    if (!cached.pending && m_connected && (m_capabilities & HasBitmapIcons)) {
        cached.pending = true;
        fetchIcon(window.id, window.iconSerial);
    }
    // The old icon until the new one arrives
    return cached.icon;
}

void WindowSource::deliverIcon(const QString &id, quint32 serial, const QByteArray &data)
{
    if (indexOf(id) < 0)
        return;
    CachedIcon &cached = m_icons[id];
    cached.pending = false;
    QIcon icon;
    QDataStream stream(data);
    stream >> icon;
    cached.serial = serial;
    cached.icon = icon;
    Q_EMIT iconChanged(id);
}

} // namespace MaiaWindows
