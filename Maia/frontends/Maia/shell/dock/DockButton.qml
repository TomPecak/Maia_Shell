import QtQuick
import QtQuick.Controls.Basic
import org.kde.kirigami as Kirigami

import MaiaFrontend

// Button placed in the dock, look taken from the Quickshell dock (Launcher.qml).
// Size and position are set by the dock layout.
//
// QtQuick.Controls.Basic is used explicitly, so the look does not depend on
// the Qt Quick Controls style of the platform (e.g. org.kde.breeze).
Button {
    id: control

    // Icon: anything Kirigami.Icon accepts - a theme icon name ("konsole"), a file
    // (Qt.resolvedUrl("../../assets/pngegg.png")) or a QIcon (the icon of a window from the task manager)
    property var iconSource
    // State indicator next to the button, on the side of the screen edge the dock is attached to:
    // a dot for a running application, a longer pill for the active one
    property bool running: false
    property bool active: false
    property int edge: Qt.BottomEdge

    hoverEnabled: true
    padding: 8

    // Scale effect: pressed -> 90%, hovered -> 108%, default -> 100%
    scale: control.pressed ? 0.90 : (control.hovered ? 1.08 : 1.0)
    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    // Monochrome icons are drawn in the text color of the mode
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: Theme.label

    contentItem: Kirigami.Icon {
        source: control.iconSource
    }

    background: Rectangle {
        radius: control.width * 0.2

        // A plate (white, in the dark a dark grey), lighter or darker under the pointer and while
        // pressed or checked (the App Library button while the library is open)
        color: control.pressed || control.checked ? Theme.platePressed
             : control.hovered ? Theme.plateHover
             : Theme.plate
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
    }

    Rectangle {
        id: indicator

        readonly property bool vertical: control.edge === Qt.LeftEdge || control.edge === Qt.RightEdge
        readonly property real length: control.active ? 14 : 5
        // Between the button and the dock border (the dock padding is 10 px)
        readonly property real gap: 3

        visible: control.running
        width: vertical ? 4 : length
        height: vertical ? length : 4
        radius: 2
        color: control.active ? Theme.label : Theme.secondaryLabel

        x: control.edge === Qt.LeftEdge ? -gap - width
         : control.edge === Qt.RightEdge ? control.width + gap
         : (control.width - width) / 2
        y: control.edge === Qt.TopEdge ? -gap - height
         : control.edge === Qt.BottomEdge ? control.height + gap
         : (control.height - height) / 2

        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    }
}
