import QtQuick
import QtQuick.Templates as T

import ".."

// Quick settings tile: a checkable tile with an icon and a label under it.
// Checked tiles are filled with the accent color.
T.AbstractButton {
    id: control

    property string iconName

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
                size: 20
                iconName: control.iconName
                tint: control.checked ? Theme.onAccent : Theme.textPrimary

                scale: control.pressed ? 0.85 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
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
