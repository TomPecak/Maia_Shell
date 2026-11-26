import QtQuick
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell
import Maia.Windows as Windows
import Maia.Notifications.Center
import Maia.Tray

import LumenFrontend

// Taskbar: a layer-shell strip at the bottom edge which reserves its area, so maximized
// windows and the flyouts are placed above it.
// Left: widgets (weather), center: start, search and the open windows,
// right: the system tray (the icons of applications, "^" for the ones they put away), network,
// volume and battery (open quick settings) and the clock (opens the calendar).
//
// The windows come from the Maia window service (Maia.Windows, Maia/services/windows): its
// TasksModel has the API of the Plasma task manager (org.kde.taskmanager), the service talks to
// KWin. Without the service (not started) the taskbar simply shows no windows.
Window {
    id: taskbar

    width: Screen.width
    height: Theme.taskbarHeight
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: true

    LayerShell.Window.scope: "lumen-taskbar"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: Theme.taskbarHeight
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // Where the taskbar begins on the screen (it is anchored to the bottom edge)
    readonly property real screenTop: Screen.height - height

    Rectangle {
        anchors.fill: parent
        color: Theme.taskbar

        Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

        // Hairline at the top edge
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.stroke
        }
    }

    // --- Left: widgets ---

    SubtleButton {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        height: 40
        highlighted: Shell.activeFlyout === "widgets"
        Accessible.name: qsTr("Widgets")
        onClicked: Shell.toggleFlyout("widgets")

        contentItem: RowLayout {
            spacing: Theme.spacingS

            LIcon {
                size: 24
                iconName: "weather-few-clouds-symbolic"
                tint: Theme.accent
            }

            Column {
                LText { text: "18°C"; font.pixelSize: Theme.fontCaption; font.weight: Font.DemiBold }
                LText { text: qsTr("Partly sunny"); font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
            }
        }
    }

    // One entry per window, in the order the windows were opened
    Windows.TasksModel {
        id: tasksModel

        groupMode: Windows.TasksModel.GroupDisabled
        sortMode: Windows.TasksModel.SortManual
    }

    // --- Center: start, search, open windows ---

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        SubtleButton {
            id: startButton

            width: 40
            height: 40
            highlighted: Shell.activeFlyout === "start"
            Accessible.name: qsTr("Start")
            onClicked: Shell.toggleFlyout("start")

            contentItem: Item {
                StartGlyph {
                    anchors.centerIn: parent
                    size: 22
                    active: startButton.highlighted
                    scale: startButton.pressed ? 0.82 : 1.0
                    Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
                }
            }
        }

        // Search opens the start menu with the search field focused
        SubtleButton {
            width: 40
            height: 40
            Accessible.name: qsTr("Search")
            onClicked: Shell.toggleFlyout("start")

            contentItem: Item {
                LIcon {
                    anchors.centerIn: parent
                    size: 18
                    iconName: "system-search-symbolic"
                }
            }
        }

        Repeater {
            model: tasksModel

            // A click activates the window; on the active window it minimizes it (like Windows)
            delegate: TaskbarButton {
                iconSource: model.decoration
                running: true
                active: model.IsActive === true
                Accessible.name: model.display
                onClicked: {
                    const taskIndex = tasksModel.makeModelIndex(index)
                    if (model.IsActive)
                        tasksModel.requestToggleMinimized(taskIndex)
                    else
                        tasksModel.requestActivate(taskIndex)
                    Shell.closeFlyouts()
                }
            }
        }
    }

    // --- Right: system tray and clock ---

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        // The icons the applications put away (passive), in the overflow; "^" only when there are
        TaskbarButton {
            id: overflowButton

            width: 32
            visible: trayHidden.count > 0
            iconName: "go-up-symbolic"
            iconSize: 14
            tintIcon: true
            active: Shell.trayOverflowOpen
            Accessible.name: qsTr("Show hidden icons")
            onClicked: {
                const at = mapToItem(null, width, 0)
                Shell.toggleTrayOverflow(at.x, taskbar.screenTop + at.y)
            }

            TrayItemsModel {
                id: trayHidden

                filter: TrayItemsModel.Passive
            }
        }

        // The icons the applications show (active, or needing attention), in the order of the tray
        Repeater {
            model: TrayItemsModel {
                filter: TrayItemsModel.Shown
            }

            // An item around the button: the roles do not hide the button's own properties
            delegate: Item {
                id: trayItem

                required property int itemId
                required property string currentIconSource
                required property bool currentIconIsMask
                required property string overlayIconSource
                required property bool needsAttention
                required property bool hasMenu
                required property bool itemIsMenu
                required property string title
                required property string toolTipTitle
                required property string toolTipText

                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                width: trayButton.implicitWidth
                height: trayButton.implicitHeight

                TrayIconButton {
                    id: trayButton

                    anchors.fill: parent
                    source: trayItem.currentIconSource
                    isMask: trayItem.currentIconIsMask
                    overlaySource: trayItem.overlayIconSource
                    needsAttention: trayItem.needsAttention
                    hasMenu: trayItem.hasMenu
                    itemIsMenu: trayItem.itemIsMenu
                    highlighted: Shell.trayMenuItemId === trayItem.itemId
                    toolTip: [trayItem.toolTipTitle !== "" ? trayItem.toolTipTitle : trayItem.title, trayItem.toolTipText]
                             .filter(t => t !== "").join("\n")
                    Accessible.name: trayItem.title

                    onActivated: {
                        Shell.closeFlyouts()
                        Tray.activate(trayItem.itemId, 0, 0, taskbar)
                    }
                    onSecondaryActivated: Tray.secondaryActivate(trayItem.itemId, 0, 0, taskbar)
                    onMenuRequested: {
                        const at = mapToItem(null, 0, 0)
                        Shell.openTrayMenu(trayItem.itemId, at.x, taskbar.screenTop + at.y)
                    }
                    onContextMenuRequested: Tray.contextMenu(trayItem.itemId, 0, 0)
                    onScrolled: (delta, horizontal) => Tray.scroll(trayItem.itemId, delta, horizontal)
                }
            }
        }

        // Network, volume and battery: opens quick settings
        SubtleButton {
            height: 40
            highlighted: Shell.activeFlyout === "quickSettings"
            leftPadding: Theme.spacingM
            rightPadding: Theme.spacingM
            Accessible.name: qsTr("Quick settings")
            onClicked: Shell.toggleFlyout("quickSettings")

            contentItem: Row {
                spacing: Theme.spacingM

                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: Shell.airplaneMode ? "network-flightmode-on-symbolic" : Shell.wifiIconName
                }
                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: typeof audioBackend !== "undefined" && audioBackend && audioBackend.prefferedOutputMuted
                          ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
                }
                // A computer without a battery shows none
                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Shell.hasBattery
                    iconName: Shell.batteryIconName
                }
            }
        }

        // Clock: opens the calendar and notifications
        SubtleButton {
            height: 40
            highlighted: Shell.activeFlyout === "calendar"
            leftPadding: Theme.spacingM
            rightPadding: Theme.spacingM
            Accessible.name: qsTr("Clock and notifications")
            onClicked: Shell.toggleFlyout("calendar")

            contentItem: RowLayout {
                spacing: Theme.spacingM

                Column {
                    LText {
                        anchors.right: parent.right
                        text: Shell.now.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                        font.pixelSize: Theme.fontCaption
                    }
                    LText {
                        anchors.right: parent.right
                        text: Shell.now.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                        font.pixelSize: Theme.fontCaption
                    }
                }

                // A copy or another job runs: how far all of them are (the details: in the center)
                ProgressRing {
                    implicitWidth: 18
                    implicitHeight: 18
                    thickness: 3
                    visible: jobs.runningCount > 0
                    value: jobs.percent >= 0 ? jobs.percent / 100 : 0.25
                    Accessible.name: jobs.percent >= 0 ? qsTr("Copying, %1 %").arg(jobs.percent) : qsTr("Copying")

                    JobsModel {
                        id: jobs

                        runningOnly: true
                    }

                    // Unknown progress: a quarter that turns
                    RotationAnimator on rotation {
                        running: jobs.runningCount > 0 && jobs.percent < 0
                        from: 0
                        to: 360
                        duration: 1200
                        loops: Animation.Infinite
                    }
                }

                // Quiet: do not disturb is on (by the user or an application)
                LIcon {
                    visible: NotificationCenter.doNotDisturbActive
                    iconName: "notifications-disabled-symbolic"
                    size: 16
                    tint: Theme.textSecondary
                }

                // How many notifications the center has
                Rectangle {
                    implicitWidth: Math.max(20, badge.implicitWidth + Theme.spacingS)
                    implicitHeight: 20
                    radius: 10
                    color: Theme.accent
                    visible: NotificationCenter.count > 0

                    LText {
                        id: badge

                        anchors.centerIn: parent
                        text: NotificationCenter.count > 99 ? "99+" : NotificationCenter.count
                        color: Theme.onAccent
                        font.pixelSize: Theme.fontCaption
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
