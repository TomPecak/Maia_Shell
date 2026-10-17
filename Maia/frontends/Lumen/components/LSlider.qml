import QtQuick
import QtQuick.Templates as T

import ".."

// Fluent style slider: thin track filled with the accent color, round thumb with an accent
// dot which grows on hover and shrinks while dragged
T.Slider {
    id: control

    hoverEnabled: true
    implicitWidth: 200
    implicitHeight: 32

    background: Item {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: 4

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.controlStrong
        }

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: Theme.accent

            Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 20
        height: 20
        radius: 10
        color: Theme.dark ? "#454545" : "#FFFFFF"
        border.width: 1
        border.color: Theme.stroke

        Rectangle {
            anchors.centerIn: parent
            width: control.pressed ? 10 : control.hovered ? 14 : 12
            height: width
            radius: width / 2
            color: Theme.accent

            Behavior on width { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
        }
    }
}
