import QtQuick
import QtQuick.Controls
import QtQuick.Effects

import Maia.Client

import "../FishUI" as FishUI

Item {
    id: control

    property bool searchMode: false
    property bool dragStarted: false
    property var dragItemIndex: index
    property var dragSource: null

    property int pageIndex: 0
    property int pageCount: 0

    //IconItem {
    MIconItem {
        id: icon

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: label.top
        anchors.margins: FishUI.Units.largeSpacing * 2

        width: height
        height: width

        source: model.iconName
        visible: !dragStarted

        layer.enabled: iconMouseArea.pressed

            layer.effect: MultiEffect {
                id: iconColorize
                anchors.fill: icon
                source: icon
                colorizationColor: "#000000"
                colorization: 0.5
            }
    }

    // Rectangle{
    //     id: iconRect
    //     anchors.fill: icon

    //     color: "red"
    // }

    MouseArea {
        id: iconMouseArea
        anchors.fill: icon
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.axis: Drag.XAndYAxis
        hoverEnabled: true

        propagateComposedEvents: true

         onClicked: (mouse)=> {
             if (mouse.button === Qt.LeftButton)
                 launcherModel.launch(model.appId)
             else if (mouse.button === Qt.RightButton) {
    //             uninstallItem.visible = appManager.isCutefishOS()
    //             _itemMenu.updateActions()
    //             _itemMenu.popup()
             }
            mouse.accepted = false
         }

    //     onPositionChanged: {
    //         if (pressed) {
    //             if (mouse.source !== Qt.MouseEventSynthesizedByQt) {
    //                 drag.target = icon
    //                 icon.grabToImage(function(result) {
    //                     control.Drag.imageSource = result.url
    //                 })
    //             } else {
    //                 drag.target = null
    //             }
    //         }
    //     }

    //     onReleased: {
    //         drag.target = null
    //     }
    }


    Label {
        id: label

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            margins: FishUI.Units.smallSpacing
        }

        // visible: !dragStarted

        text: model.name
        elide: Text.ElideRight
        textFormat: Text.PlainText
        maximumLineCount: 2
        wrapMode: "WordWrap"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignTop
        width: parent.width - 2 * FishUI.Units.smallSpacing
        height: fontMetrics.height * 2
        color: "white"

    }
}
