import QtQuick
import QtQuick.Controls

MenuSeparator {
    id: separator
    padding: 0

    topPadding: 3
    bottomPadding: 5

    rightPadding: 1
    leftPadding: 1

    contentItem: Rectangle {
        implicitHeight: 1
        width: separator.availableWidth
        color: "#aca899"
    }
}
