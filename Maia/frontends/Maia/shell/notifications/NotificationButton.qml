import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// A button of a notification: a label, a glyph shipped with the frontend (mask) or an icon of
// the theme. The target is at least 44 px high (touch); a round one may draw less than its target
// (plateSize), so that it stays light on the card.
Item {
    id: button

    // The label; a round button shows only its icon, the text is for screen readers
    property string text
    // assets/icons, tinted
    property url glyph
    // A name of the icon theme, in its own colors
    property string themeIcon
    // Round, around an icon (close, expand, a media key); otherwise a wide plate with the label
    property bool round: false
    property real plateSize: 28
    property bool prominent: false
    property color prominentColor: Theme.accent
    // Between the label and the plate's sides
    property real sidePadding: 16
    property int fontSize: 14
    readonly property bool hovered: area.containsMouse
    readonly property bool pressed: area.pressed

    signal clicked()

    implicitWidth: round ? 44 : label.implicitWidth + 2 * sidePadding
    implicitHeight: 44

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: button.clicked()

    Rectangle {
        id: plate

        anchors.centerIn: parent
        width: button.round ? button.plateSize : parent.width
        height: button.round ? button.plateSize : 40
        radius: button.round ? width / 2 : 12
        color: button.prominent ? (area.pressed ? Qt.darker(button.prominentColor, 1.12) : button.prominentColor)
             : area.pressed ? Theme.secondaryFillHover
             : area.containsMouse ? Theme.fill
             : button.round ? "transparent" : Theme.secondaryFill
        scale: area.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            visible: button.glyph.toString().length > 0
            source: visible ? button.glyph : ""
            isMask: true
            color: button.prominent ? "white" : Theme.label
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            visible: button.themeIcon.length > 0
            source: button.themeIcon
        }

        Text {
            id: label

            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 16)
            visible: !button.round
            text: button.text
            elide: Text.ElideRight
            color: button.prominent ? "white" : Theme.label
            font.pixelSize: button.fontSize
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
