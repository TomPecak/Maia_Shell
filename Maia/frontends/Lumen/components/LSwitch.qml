import QtQuick
import QtQuick.Templates as T

import ".."

// Fluent style toggle switch: outlined track with a small knob when off,
// accent track with a larger knob when on
T.Switch {
    id: control

    hoverEnabled: true
    implicitWidth: 40
    implicitHeight: 20

    indicator: Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: control.checked ? (control.hovered ? Theme.accentHover : Theme.accent)
                               : (control.hovered ? Theme.subtleHover : "transparent")
        border.width: control.checked ? 0 : 1
        border.color: Theme.textSecondary

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            readonly property real size: control.pressed ? 14 : control.checked || control.hovered ? 14 : 12

            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? parent.width - width - 4 : 4
            width: control.pressed ? size + 3 : size
            height: size
            radius: height / 2
            color: control.checked ? Theme.onAccent : Theme.textSecondary

            Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
            Behavior on width { NumberAnimation { duration: Theme.durationFast } }
            Behavior on height { NumberAnimation { duration: Theme.durationFast } }
        }
    }

    contentItem: Item {}
}
