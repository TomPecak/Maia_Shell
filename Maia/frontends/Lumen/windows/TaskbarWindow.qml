import QtQuick
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell

import ".."
import "../components"

// Taskbar: a layer-shell strip at the bottom edge which reserves its area, so maximized
// windows and the flyouts are placed above it.
// Left: widgets (weather), center: start, search and pinned applications,
// right: system tray (opens quick settings) and the clock (opens the calendar).
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

    // --- Center: start, search, pinned applications ---

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
                    scale: startButton.pressed ? 0.82 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
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
            model: Shell.taskbarApps

            delegate: TaskbarButton {
                required property var modelData

                iconName: modelData.icon
                running: modelData.running
                Accessible.name: modelData.name
                onClicked: Shell.launch(modelData.exec)
            }
        }
    }

    // --- Right: system tray and clock ---

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        // Hidden tray icons (mock)
        TaskbarButton {
            width: 32
            iconName: "go-up-symbolic"
            iconSize: 14
            tintIcon: true
            Accessible.name: qsTr("Show hidden icons")
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
                    iconName: Shell.wifiEnabled && !Shell.airplaneMode ? "network-wireless-signal-excellent-symbolic"
                                                                   : "network-flightmode-on-symbolic"
                }
                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: typeof audioBackend !== "undefined" && audioBackend && audioBackend.prefferedOutputMuted
                          ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
                }
                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "battery-080-symbolic"
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

                // Number of unread notifications
                Rectangle {
                    implicitWidth: Math.max(20, badge.implicitWidth + Theme.spacingS)
                    implicitHeight: 20
                    radius: 10
                    color: Theme.accent
                    visible: Shell.notifications.count > 0

                    LText {
                        id: badge

                        anchors.centerIn: parent
                        text: Shell.notifications.count
                        color: Theme.onAccent
                        font.pixelSize: Theme.fontCaption
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
