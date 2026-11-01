import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// Search field of iPadOS: a rounded grey field with a magnifier, a placeholder, a cursor in the
// accent color and a clear button while it holds text.
Rectangle {
    id: field

    property alias text: input.text
    property alias placeholderText: placeholder.text
    // The text input, for keyboard handling and focus
    readonly property alias input: input

    implicitHeight: 40
    radius: 10
    color: Theme.fill

    Kirigami.Icon {
        id: magnifier

        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        source: "search"
        isMask: true
        color: Theme.secondaryLabel
    }

    TextInput {
        id: input

        anchors.left: magnifier.right
        anchors.leftMargin: 8
        anchors.right: clearButton.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: Theme.label
        selectionColor: Theme.accent
        selectedTextColor: "white"
        font.pixelSize: 17

        // Blinks like the system cursor, restarting visible after every edit or move
        cursorDelegate: Rectangle {
            id: cursor

            width: 2
            color: Theme.accent
            visible: input.cursorVisible && blink.on

            QtObject {
                id: blink

                property bool on: true
            }

            Timer {
                interval: Qt.styleHints.cursorFlashTime / 2
                repeat: true
                running: input.activeFocus
                onTriggered: blink.on = !blink.on
            }

            Connections {
                target: input

                function onCursorPositionChanged() { blink.on = true }
                function onTextChanged() { blink.on = true }
            }
        }
    }

    Text {
        id: placeholder

        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: Theme.secondaryLabel
        font: input.font
        visible: input.text.length === 0 && input.preeditText.length === 0
    }

    // Clears the text (the xmark.circle.fill of iPadOS)
    Item {
        id: clearButton

        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? 24 : 0
        height: 24
        visible: input.text.length > 0

        Rectangle {
            anchors.centerIn: parent
            width: 18
            height: 18
            radius: 9
            color: clearArea.pressed ? Theme.secondaryLabel : Theme.tertiaryLabel

            Repeater {
                model: [45, -45]

                Rectangle {
                    required property int modelData

                    anchors.centerIn: parent
                    width: 8
                    height: 1.6
                    radius: 0.8
                    rotation: modelData
                    color: Theme.surface
                }
            }
        }

        MouseArea {
            id: clearArea

            anchors.fill: parent
            anchors.margins: -4
            onClicked: {
                input.text = ""
                input.forceActiveFocus()
            }
        }
    }
}
