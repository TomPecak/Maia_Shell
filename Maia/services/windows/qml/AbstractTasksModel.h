#pragma once

// The data roles of the task models, by the names of KDE Plasma (libtaskmanager,
// AbstractTasksModel::AdditionalRoles), so QML written for org.kde.taskmanager keeps working:
//
//   tasksModel.data(index, AbstractTasksModel.IsActive)
//   delegate: ... model.AppName, model.IsMinimized, model.decoration ...
//
// The order and values are those of Plasma 6.6. Roles a Wayland client cannot know through the
// service (activities, application menu, startups, launchers) exist, but are empty or false.

#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace MaiaWindows {
namespace AbstractTasksModel {
Q_NAMESPACE
QML_ELEMENT

enum AdditionalRoles {
    AppId = Qt::UserRole + 1, // desktop entry id without ".desktop", e.g. "org.kde.konsole"
    AppName,
    GenericName,
    LauncherUrl, // "applications:org.kde.konsole.desktop"
    LauncherUrlWithoutIcon,
    WinIdList, // ids of the windows (strings, stable while the window exists)
    MimeType,
    MimeData,
    IsWindow,
    IsStartup,
    IsLauncher,
    HasLauncher,
    IsGroupParent,
    ChildCount,
    IsGroupable,
    IsActive,
    IsClosable,
    IsMovable,
    IsResizable,
    IsMaximizable,
    IsMaximized,
    IsMinimizable,
    IsMinimized,
    IsKeepAbove,
    IsKeepBelow,
    IsFullScreenable,
    IsFullScreen,
    IsShadeable,
    IsShaded,
    IsVirtualDesktopsChangeable,
    VirtualDesktops,
    IsOnAllVirtualDesktops,
    Geometry,
    ScreenGeometry,
    Activities,
    IsDemandingAttention,
    SkipTaskbar,
    SkipPager,
    AppPid,
    StackingOrder,
    LastActivated, // QDateTime (a Date in QML), invalid when never activated
    ApplicationMenuServiceName,
    ApplicationMenuObjectPath,
    IsHidden,
    CanLaunchNewInstance,
    HasNoBorder,
    CanSetNoBorder,
    IsExcludedFromCapture,
};
Q_ENUM_NS(AdditionalRoles)

} // namespace AbstractTasksModel
} // namespace MaiaWindows
