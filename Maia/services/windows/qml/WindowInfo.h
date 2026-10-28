#pragma once

// One window as the service reports it (contract struct Window, ../contract/windows.capnp), as a
// plain Qt value: the model and the tests work with it without Cap'n Proto.

#include <QList>
#include <QRect>
#include <QString>
#include <QStringList>

namespace MaiaWindows {

// The state* bits of the contract (checked against the generated code in ServiceConnection.cpp)
enum State : quint32 {
    Active = 0x1,
    Minimized = 0x2,
    Maximized = 0x4,
    Fullscreen = 0x8,
    KeepAbove = 0x10,
    KeepBelow = 0x20,
    OnAllDesktops = 0x40,
    DemandsAttention = 0x80,
    Closeable = 0x100,
    Minimizable = 0x200,
    Maximizable = 0x400,
    Fullscreenable = 0x800,
    SkipTaskbar = 0x1000,
    Shadeable = 0x2000,
    Shaded = 0x4000,
    Movable = 0x8000,
    Resizable = 0x10000,
    VirtualDesktopChangeable = 0x20000,
    SkipSwitcher = 0x40000,
};

// The cap* bits of the contract: what the service can do
enum Capability : quint32 {
    CanActivate = 0x1,
    CanClose = 0x2,
    CanMinimize = 0x4,
    CanMaximize = 0x8,
    CanFullscreen = 0x10,
    CanKeepAboveBelow = 0x20,
    CanMoveResize = 0x40,
    CanChangeVirtualDesktops = 0x80,
    HasBitmapIcons = 0x100,
    CanLaunch = 0x200,
};

struct WindowInfo {
    QString id;
    QString title;
    QString appId; // desktop entry id, e.g. "org.kde.konsole.desktop"; empty when not identified
    QString rawAppId;
    QString appName;
    QString genericName;
    QString iconName;
    quint32 iconSerial = 0; // > 0: the compositor has a bitmap icon
    QString launcherUrl;
    quint32 pid = 0;
    quint32 states = 0;
    QRect geometry;
    QStringList virtualDesktops;
    QString parentId;
    qint64 lastActivated = 0; // ms since 1970, 0 = never
    bool canLaunchNewInstance = false;

    bool has(State state) const { return (states & state) != 0; }

    bool operator==(const WindowInfo &) const = default;
};

} // namespace MaiaWindows
