import QtQuick
import QtQuick.Controls

MenuSeparator {
    id: separator
    padding: 0

    topPadding: 3
    bottomPadding: 3

    rightPadding: 10
    leftPadding: 10

    contentItem: Rectangle {
        implicitHeight: 1
        color: "#e1e1e1"
        width: separator.availableWidth
    }
}
