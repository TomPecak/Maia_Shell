import QtQuick

import LumenFrontend

// Toolbar button of the File Explorer: a symbolic icon, an optional label, an optional
// dropdown arrow and a tooltip. Disabled buttons are dimmed.
SubtleButton {
    id: control

    property string iconName
    property int iconSize: 16
    property bool dropdown: false
    property string toolTip
    readonly property bool showText: text.length > 0

    implicitWidth: Math.max(32, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: 32
    padding: 0
    leftPadding: showText ? Theme.spacingS + 2 : 0
    rightPadding: showText || dropdown ? Theme.spacingS + 2 : 0
    opacity: enabled ? 1 : 0.4
    Accessible.name: toolTip.length > 0 ? toolTip : text

    Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: 32

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 6

            LIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.iconName.length > 0
                iconName: control.iconName
                size: control.iconSize
            }

            LText {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.showText
                text: control.text
            }

            LIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.dropdown
                iconName: "go-down-symbolic"
                size: 10
                tint: Theme.textSecondary
            }
        }
    }

    ExplorerToolTip {
        text: control.toolTip
        visible: control.hovered && !control.pressed && control.toolTip.length > 0
    }
}
