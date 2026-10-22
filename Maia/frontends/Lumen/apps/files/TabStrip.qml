pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Title bar of the File Explorer: the tabs, the new tab button and the window buttons.
// The empty space moves the window (drag) and maximizes it (double click).
Item {
    id: strip

    required property var explorer

    readonly property int windowButtonsWidth: 3 * 46
    // The tabs share the free space, between a minimum and a maximum width
    readonly property real tabWidth: {
        const free = width - 8 - newTabButton.width - windowButtonsWidth - 56
        return Math.max(100, Math.min(240, free / Math.max(1, explorer.tabs.length)))
    }

    implicitHeight: 40

    // Behind the tabs: moving and maximizing the window
    DragHandler {
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: {
            if (active)
                strip.explorer.startSystemMove()
        }
    }

    TapHandler {
        onDoubleTapped: strip.explorer.toggleMaximized()
    }

    Row {
        id: tabsRow

        x: 8
        anchors.bottom: parent.bottom

        Repeater {
            model: strip.explorer.tabs

            delegate: TabButton {}
        }

        ExplorerButton {
            id: newTabButton

            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
            width: 32
            iconName: "list-add-symbolic"
            toolTip: qsTr("New tab (Ctrl+T)")
            onClicked: strip.explorer.newTab("start")
        }
    }

    // --- Window buttons ---

    Row {
        anchors.top: parent.top
        anchors.right: parent.right

        WindowButton {
            glyph: "minimize"
            Accessible.name: qsTr("Minimize")
            onClicked: strip.explorer.showMinimized()
        }
        WindowButton {
            glyph: strip.explorer.maximized ? "restore" : "maximize"
            Accessible.name: strip.explorer.maximized ? qsTr("Restore") : qsTr("Maximize")
            onClicked: strip.explorer.toggleMaximized()
        }
        WindowButton {
            closeButton: true
            glyph: "close"
            Accessible.name: qsTr("Close")
            onClicked: strip.explorer.close()
        }
    }

    // --- Building blocks ---

    component TabButton: T.AbstractButton {
        id: tabButton

        required property var modelData
        required property int index

        readonly property var tab: modelData
        readonly property bool current: index === strip.explorer.currentIndex
        readonly property bool nextIsCurrent: index + 1 === strip.explorer.currentIndex

        width: strip.tabWidth
        height: 34
        hoverEnabled: true
        Accessible.role: Accessible.PageTab
        Accessible.name: tab.title
        onClicked: strip.explorer.currentIndex = index

        // A new tab fades in (the delegates are recreated when the list of tabs changes,
        // only the added tab animates)
        Component.onCompleted: {
            if (tab === strip.explorer.lastAddedTab) {
                opacity = 0
                appear.start()
            }
        }
        OpacityAnimator { id: appear; target: tabButton; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }

        // The middle button closes the tab
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: strip.explorer.closeTab(tabButton.index)
        }

        background: Item {
            // The current tab merges with the toolbar below it
            Rectangle {
                anchors.fill: parent
                topLeftRadius: Theme.radiusMedium
                topRightRadius: Theme.radiusMedium
                color: Theme.windowToolbar
                opacity: tabButton.current ? 1 : 0

                Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.bottomMargin: 4
                radius: Theme.radiusSmall + 2
                color: tabButton.pressed ? Theme.subtlePressed : Theme.subtleHover
                opacity: !tabButton.current && tabButton.hovered ? 1 : 0

                Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
            }

            // Separator between inactive tabs
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: 1
                height: 16
                color: Theme.divider
                visible: !tabButton.current && !tabButton.nextIsCurrent
            }
        }

        contentItem: Item {
            LIcon {
                id: tabIcon

                x: 12
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -1
                iconName: tabButton.tab.icon
                tinted: false
                size: 16
            }

            LText {
                anchors.left: tabIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: closeTabButton.left
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: tabIcon.verticalCenter
                text: tabButton.tab.title
                font.pixelSize: Theme.fontCaption + 1
                color: tabButton.current ? Theme.textPrimary : Theme.textSecondary
            }

            SubtleButton {
                id: closeTabButton

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: tabIcon.verticalCenter
                width: 24
                height: 24
                padding: 0
                opacity: tabButton.current || tabButton.hovered ? 1 : 0
                enabled: opacity > 0
                Accessible.name: qsTr("Close tab")
                onClicked: strip.explorer.closeTab(tabButton.index)

                contentItem: Item {
                    LIcon {
                        anchors.centerIn: parent
                        iconName: "window-close-symbolic"
                        size: 10
                        tint: Theme.textSecondary
                    }
                }
            }
        }
    }

    // Caption button with a thin drawn glyph: "minimize", "maximize", "restore" or "close"
    component WindowButton: T.AbstractButton {
        id: windowButton

        property string glyph
        property bool closeButton: false
        readonly property color glyphColor: closeButton && hovered ? "white" : Theme.textPrimary

        width: 46
        height: 40
        hoverEnabled: true

        background: Rectangle {
            color: windowButton.closeButton
                   ? (windowButton.pressed ? Theme.closePressed : windowButton.hovered ? Theme.closeHover : "transparent")
                   : (windowButton.pressed ? Theme.subtlePressed : windowButton.hovered ? Theme.subtleHover : "transparent")
            // The close button follows the rounded corner of the window
            topRightRadius: windowButton.closeButton && !strip.explorer.maximized ? Theme.radiusMedium : 0

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }

        contentItem: Item {
            Item {
                anchors.centerIn: parent
                width: 10
                height: 10

                // Minimize: a line
                Rectangle {
                    visible: windowButton.glyph === "minimize"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 1
                    color: windowButton.glyphColor
                }

                // Maximize: a square
                Rectangle {
                    visible: windowButton.glyph === "maximize"
                    anchors.fill: parent
                    radius: 1.5
                    color: "transparent"
                    border.width: 1
                    border.color: windowButton.glyphColor
                }

                // Restore: a square with another one behind it
                Item {
                    anchors.fill: parent
                    visible: windowButton.glyph === "restore"

                    Rectangle {
                        y: 2
                        width: 8
                        height: 8
                        radius: 1.5
                        color: "transparent"
                        border.width: 1
                        border.color: windowButton.glyphColor
                    }
                    Rectangle { x: 2; width: 7; height: 1; color: windowButton.glyphColor }
                    Rectangle { x: 9; y: 0; width: 1; height: 8; color: windowButton.glyphColor }
                }

                // Close: a cross
                Repeater {
                    model: windowButton.glyph === "close" ? [45, -45] : []

                    delegate: Rectangle {
                        required property int modelData

                        anchors.centerIn: parent
                        width: 13
                        height: 1
                        rotation: modelData
                        antialiasing: true
                        color: windowButton.glyphColor
                    }
                }
            }
        }
    }
}
