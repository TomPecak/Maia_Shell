import QtQuick

import ".."

// Divider between groups of LMenu items
Item {
    width: parent ? parent.width : 0
    implicitHeight: 2 * Theme.spacingXS + 1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.divider
    }
}
