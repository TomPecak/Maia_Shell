import QtQuick
import QtQuick.Controls

Menu {
    id: contextMenu

    leftPadding: 3
    rightPadding: 3
    topPadding: 4
    bottomPadding: 4

    property bool active: true

    delegate: GMenuItem{
        id: delegateItem
        Binding{
            delegateItem.active: contextMenu.active
        }
    }

    background: Rectangle{
        color: "#ffffff"
        radius: 6

        implicitWidth: 221
        implicitHeight: 40


        border.width: 1
        border.color: "#e1e1e1"
    }
}
