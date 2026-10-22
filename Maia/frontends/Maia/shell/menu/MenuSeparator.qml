import QtQuick

// Separator of MenuPanel. The thin variant divides rows, the thick one (group: true)
// divides groups of rows, like in the menus of iPadOS.
Item {
    property bool group: false

    width: parent ? parent.width : 0
    implicitHeight: group ? 14 : 1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: parent.group ? 8 : 1
        color: parent.group ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0.24, 0.24, 0.26, 0.14)
    }
}
