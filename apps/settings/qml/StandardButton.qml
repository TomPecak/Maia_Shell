import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Fluent standard button: a control surface with a hairline border, for secondary actions.
// destructive: the text in the critical color (Forget, Turn off).
T.Button {
    id: control

    property bool destructive: false
    property string iconName

    hoverEnabled: true
    padding: Theme.spacingS
    leftPadding: Theme.spacingL
    rightPadding: Theme.spacingL
    spacing: Theme.spacingS

    implicitWidth: Math.max(implicitBackgroundWidth, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    opacity: enabled ? 1 : 0.45

    contentItem: Row {
        spacing: control.spacing

        LIcon {
            visible: control.iconName.length > 0
            iconName: control.iconName
            size: 16
            tint: label.color
            anchors.verticalCenter: parent.verticalCenter
        }

        LText {
            id: label

            text: control.text
            color: control.destructive ? Theme.critical : Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.pressed ? Theme.subtlePressed : control.hovered ? Qt.tint(Theme.control, Theme.subtleHover) : Theme.control
        border.width: 1
        border.color: control.visualFocus ? Theme.accent : Theme.stroke

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }
}
