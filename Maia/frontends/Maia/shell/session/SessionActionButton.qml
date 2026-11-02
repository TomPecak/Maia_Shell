import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// A round action of the session screen, like the buttons of the iPadOS Control Center: a circle
// with a symbol and the name below it, in the colors of the light or dark mode.
Item {
    id: action

    property string text
    property string iconName
    // The destructive action (shut down) is a red circle with a white symbol, like the power
    // control of iPadOS; the others a grey fill with a symbol in the text color
    property bool destructive: false
    // Selected with the keyboard: Enter carries it out
    property bool selected: false

    signal clicked()

    readonly property real circle: 72

    implicitWidth: 104
    implicitHeight: circle + 10 + label.implicitHeight

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: action.clicked()

    // Keyboard focus ring, the accent color of iPadOS on a dark background
    Rectangle {
        anchors.centerIn: plate
        width: action.circle + 10
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 3
        border.color: Theme.accent
        visible: action.selected
    }

    Rectangle {
        id: plate

        anchors.horizontalCenter: parent.horizontalCenter
        width: action.circle
        height: action.circle
        radius: width / 2
        color: action.destructive ? (area.containsMouse || action.selected ? Theme.redHover : Theme.red)
             : area.containsMouse || action.selected ? Theme.secondaryFillHover : Theme.secondaryFill
        scale: area.pressed ? 0.9 : area.containsMouse ? 1.05 : 1

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: 180; easing.type: Easing.OutCubic }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 32
            height: 32
            source: action.iconName
            isMask: true
            color: action.destructive ? "white" : Theme.label
        }
    }

    Text {
        id: label

        anchors.top: plate.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: action.text
        color: Theme.label
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    MouseArea {
        id: area

        anchors.fill: plate
        hoverEnabled: true
        onClicked: action.clicked()
    }
}
