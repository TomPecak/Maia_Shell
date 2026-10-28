import QtQuick
import org.kde.kirigami as Kirigami

import LumenFrontend

// Taskbar button with an icon and a state indicator under it:
// a short gray pill for a running application, a longer accent pill for an active one
// (e.g. the start button while the start menu is open).
//
// The icon is either a theme icon by name (iconName) or any icon source (iconSource), e.g. the
// QIcon of a window from the task manager.
SubtleButton {
    id: control

    property string iconName
    property var iconSource
    property int iconSize: 24
    property bool tintIcon: false
    property bool running: false
    property bool active: false

    readonly property bool hasIconSource: iconSource !== undefined && iconSource !== null

    implicitWidth: 40
    implicitHeight: 40
    padding: 0
    highlighted: active

    contentItem: Item {
        Item {
            anchors.centerIn: parent
            width: control.iconSize
            height: control.iconSize

            // Icon "press" effect
            scale: control.pressed ? 0.82 : 1.0
            Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }

            LIcon {
                anchors.centerIn: parent
                visible: !control.hasIconSource
                size: control.iconSize
                iconName: control.iconName
                tinted: control.tintIcon
            }

            Kirigami.Icon {
                anchors.fill: parent
                visible: control.hasIconSource
                source: control.hasIconSource ? control.iconSource : ""
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2

        height: 3
        radius: 1.5
        width: control.active ? 16 : control.running ? 6 : 0
        opacity: width > 0 ? 1 : 0
        color: control.active ? Theme.accent : Theme.textTertiary

        Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
        Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }
}
