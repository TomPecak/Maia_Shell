import QtQuick

// Button placed in the dock. Size and position are set by the dock.
Rectangle {
    id: button

    signal clicked()

    color: "blue"
    radius: 3

    MouseArea {
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
