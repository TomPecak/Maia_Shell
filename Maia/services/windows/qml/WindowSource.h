#pragma once

// Where the windows come from, for the models of this module.
//
// WindowSource keeps the window list of the process (in the GUI thread) and tells about every
// change; the commands are virtual. ServiceConnection is the real source (the Cap'n Proto service),
// the tests use a fake one. Every TasksModel of a process shares one source, so the process keeps
// one connection and one copy of the list, however many models (taskbar, dock, switcher) it has.
//
// When the service goes away, the list stays as it was (no flicker of the taskbar); the snapshot
// after the reconnection is applied as differences.

#include "WindowInfo.h"

#include <QHash>
#include <QIcon>
#include <QObject>

namespace MaiaWindows {

class WindowSource : public QObject
{
    Q_OBJECT

public:
    explicit WindowSource(QObject *parent = nullptr);

    // The windows in the order they appeared
    const QList<WindowInfo> &windows() const { return m_windows; }
    const WindowInfo *window(const QString &id) const;

    bool isConnected() const { return m_connected; }
    quint32 capabilities() const { return m_capabilities; }

    // The bitmap icon of a window: from the cache, or null while it is being fetched
    // (iconChanged(id) follows when it arrives)
    QIcon bitmapIcon(const WindowInfo &window);

    // --- Commands (fire and forget; the result shows up as a change of the window) ---
    virtual void activate(const QString &id) = 0;
    virtual void close(const QString &id) = 0;
    // flag: one of Minimized, Maximized, Fullscreen, KeepAbove, KeepBelow
    virtual void setState(const QString &id, State flag, bool on) = 0;
    virtual void requestMove(const QString &id) = 0;
    virtual void requestResize(const QString &id) = 0;
    virtual void launchNewInstance(const QString &id) = 0;
    virtual void launch(const QString &launcherUrl) = 0;

Q_SIGNALS:
    void windowAdded(const MaiaWindows::WindowInfo &window);
    void windowChanged(const MaiaWindows::WindowInfo &before, const MaiaWindows::WindowInfo &after);
    void windowRemoved(const MaiaWindows::WindowInfo &window);
    void iconChanged(const QString &id);
    void connectedChanged();

protected:
    // For the implementations: they feed the list through these
    void applySnapshot(const QList<WindowInfo> &windows);
    void upsert(const WindowInfo &window);
    void remove(const QString &id);
    void setConnected(bool connected, quint32 capabilities = 0);
    // The icon data of the window (QIcon serialized with QDataStream, as KWin sends it)
    void deliverIcon(const QString &id, quint32 serial, const QByteArray &data);
    // Asks for the bitmap icon; the answer comes through deliverIcon
    virtual void fetchIcon(const QString &id, quint32 serial) = 0;

private:
    int indexOf(const QString &id) const;

    struct CachedIcon {
        quint32 serial = 0;
        QIcon icon;
        bool pending = false;
    };

    QList<WindowInfo> m_windows;
    QHash<QString, CachedIcon> m_icons;
    bool m_connected = false;
    quint32 m_capabilities = 0;
};

} // namespace MaiaWindows
