import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Quick settings tile: a checkable tile with an icon and a label under it.
// Checked tiles are filled with the accent color.
//
// hasMenu: the tile is split like in Windows 11: the left part toggles, the chevron on the right
// opens the tile's page (menuClicked), e.g. the list of Wi-Fi networks.
T.AbstractButton {
    id: control

    property string iconName
    property bool hasMenu: false

    signal menuClicked()

    checkable: true
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    implicitWidth: 104
    implicitHeight: tile.height + Theme.spacingS + label.implicitHeight

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checked: checked

    contentItem: Item {
        Rectangle {
            id: tile

            width: parent.width
            height: 48
            radius: Theme.radiusSmall
            color: control.checked
                   ? (control.pressed ? Theme.accentPressed : control.hovered ? Theme.accentHover : Theme.accent)
                   : (control.pressed ? Theme.subtlePressed : control.hovered ? Theme.controlStrong : Theme.control)
            border.width: control.checked ? 0 : 1
            border.color: Theme.stroke

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

            LIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: control.hasMenu ? -menuPart.width / 2 : 0
                size: 20
                iconName: control.iconName
                tint: control.checked ? Theme.onAccent : Theme.textPrimary

                scale: control.pressed ? 0.85 : 1.0
                Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
            }

            // The chevron part: takes its clicks itself, so they do not toggle
            Item {
                id: menuPart

                anchors.right: parent.right
                width: control.hasMenu ? 30 : 0
                height: parent.height
                visible: control.hasMenu

                Rectangle {
                    width: 1
                    height: parent.height - 2 * Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    color: control.checked ? Qt.rgba(Theme.onAccent.r, Theme.onAccent.g, Theme.onAccent.b, 0.3) : Theme.stroke
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 1
                    radius: Theme.radiusSmall
                    color: control.checked ? Qt.rgba(Theme.onAccent.r, Theme.onAccent.g, Theme.onAccent.b, 0.12) : Theme.subtleHover
                    opacity: menuArea.containsMouse ? 1 : 0
                    Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
                }

                LIcon {
                    anchors.centerIn: parent
                    size: 14
                    iconName: "go-next-symbolic"
                    tint: control.checked ? Theme.onAccent : Theme.textPrimary
                }

                MouseArea {
                    id: menuArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: control.menuClicked()
                }
            }
        }

        LText {
            id: label

            anchors.top: tile.bottom
            anchors.topMargin: Theme.spacingS
            width: parent.width
            text: control.text
            font.pixelSize: Theme.fontCaption
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
