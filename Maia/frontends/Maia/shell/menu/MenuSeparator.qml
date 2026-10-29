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
        // Thin: the separator color of iPadOS (60, 60, 67), lighter than its 29 % as menus show it;
        // thick: the darker band between groups of rows
        color: parent.group ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.2)
    }
}
