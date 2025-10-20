import QtQuick

import Maia.Client

Item {
    id: control

    property var iconSize: control.height * iconSizeRatio

    property alias icon: icon

    property double iconSizeRatio: 0.8
    property var iconName

    MIconItem{
        id: icon
        anchors.centerIn: parent
        width: control.iconSize
        height: control.iconSize
        source: iconName

        // Rectangle{
        //     anchors.fill: parent
        //     color: "transparent"
        //     border.width: 1
        //     border.color: "green"
        // }
    }
}
