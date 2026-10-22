pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

import LumenFrontend
import "MockFileSystem.js" as Fs

// Navigation pane: Home, the pinned folders (Quick access), This PC with the home folder and
// the drives (expandable), Network and the Recycle Bin. The current place is highlighted;
// the middle button opens a place in a new tab, the right button shows its menu.
Item {
    id: sidebar

    required property var explorer
    readonly property var tab: explorer.currentTab
    property bool pcExpanded: true

    Flickable {
        id: flickable

        anchors.fill: parent
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: column

            width: flickable.width
            topPadding: Theme.spacingS
            bottomPadding: Theme.spacingS

            NavItem { path: "start"; label: qsTr("Home") }

            NavDivider {}

            Repeater {
                model: Fs.quickAccess()

                delegate: NavItem {
                    required property string modelData

                    path: modelData
                    pinned: true
                }
            }

            NavDivider {}

            NavItem {
                path: "this-pc"
                expandable: true
                expanded: sidebar.pcExpanded
                onToggleRequested: sidebar.pcExpanded = !sidebar.pcExpanded
            }

            // Content of This PC, slides open and closed
            Item {
                width: parent.width
                height: sidebar.pcExpanded ? pcColumn.height : 0
                clip: true

                Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }

                Column {
                    id: pcColumn

                    width: parent.width
                    opacity: sidebar.pcExpanded ? 1 : 0

                    Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }

                    NavItem { path: "home"; depth: 1 }
                    Repeater {
                        model: {
                            sidebar.explorer.revision
                            return Fs.children("this-pc").map(entry => "this-pc/" + entry.name)
                        }

                        delegate: NavItem {
                            required property string modelData

                            path: modelData
                            depth: 1
                        }
                    }
                }
            }

            NavItem { path: "network" }
            NavItem { path: "trash" }
        }
    }

    // --- Building blocks ---

    component NavItem: T.AbstractButton {
        id: item

        property string path
        property string label: { sidebar.explorer.revision; return Fs.displayName(path) }
        property int depth: 0
        property bool pinned: false
        property bool expandable: false
        property bool expanded: false
        readonly property bool current: sidebar.tab && !sidebar.tab.searching && sidebar.tab.path === path

        signal toggleRequested()

        width: parent ? parent.width : 0
        height: 32
        hoverEnabled: true
        leftInset: Theme.spacingXS
        rightInset: Theme.spacingXS
        Accessible.role: Accessible.Button
        Accessible.name: label
        onClicked: sidebar.tab.navigate(path)

        TapHandler {
            acceptedButtons: Qt.MiddleButton | Qt.RightButton
            onTapped: (eventPoint, button) => {
                if (button === Qt.MiddleButton) {
                    sidebar.explorer.newTab(item.path)
                } else {
                    const position = item.mapToItem(null, eventPoint.position.x, eventPoint.position.y)
                    sidebar.explorer.popupMenu(sidebar.explorer.placeMenu(item.path, item.pinned), position.x, position.y)
                }
            }
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: item.pressed ? Theme.subtlePressed
                 : item.current ? Theme.controlStrong
                 : item.hovered ? Theme.subtleHover
                 : "transparent"

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            // Accent pill of the current place
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: item.current ? 16 : 0
                radius: 1.5
                color: Theme.accent

                Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
            }
        }

        contentItem: Item {
            // Expand / collapse arrow
            SubtleButton {
                id: chevron

                x: 4 + item.depth * 16
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                padding: 0
                visible: item.expandable
                Accessible.name: item.expanded ? qsTr("Collapse") : qsTr("Expand")
                onClicked: item.toggleRequested()

                contentItem: Item {
                    LIcon {
                        anchors.centerIn: parent
                        iconName: "go-next-symbolic"
                        size: 10
                        tint: Theme.textSecondary
                        rotation: item.expanded ? 90 : 0

                        Behavior on rotation { RotationAnimator { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }
                    }
                }
            }

            LIcon {
                id: icon

                x: 26 + item.depth * 16
                anchors.verticalCenter: parent.verticalCenter
                iconName: Fs.iconFor(item.path)
                tinted: false
                size: 16
            }

            LText {
                anchors.left: icon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: pin.visible ? pin.left : parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: item.label
                font.weight: item.current ? Font.DemiBold : Font.Normal
            }

            LIcon {
                id: pin

                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                visible: item.pinned
                iconName: "pin-symbolic"
                size: 12
                tint: Theme.textTertiary
                opacity: item.hovered || item.current ? 1 : 0.55
            }
        }
    }

    component NavDivider: Item {
        width: parent ? parent.width : 0
        height: 13

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingL
            anchors.rightMargin: Theme.spacingL
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Theme.divider
        }
    }
}
