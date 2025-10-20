import QtQuick
import QtQuick.Layouts

import Maia.Client

import "../items"
import "../popups"

Item {
    id: root
    property bool darkMode: false

    property real windowRadius: 0.3 * height

    MTaskbarModel{
        id: taskbarModel
    }

    ApplicationModel{
        id: appModel
        Component.onCompleted: {
            console.log("DDDDDDDDDDDDUPA cutefishos application model completed")
        }
    }


    implicitHeight: 56
    implicitWidth: implicitHeight





    width: appItemView.count * root.height

    Rectangle{
        id: _background

        anchors.fill: parent
        radius: root.windowRadius
        color: "#E6E6E6"
        opacity: 0.5
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
    }

    PopupTips {
        id: popupTips
        backgroundColor: _background.color
        //blurEnabled: false
    }

    GridLayout{
        anchors.fill: parent
        anchors.topMargin: 0
        flow: Grid.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        ListView{
            id: appItemView
            orientation: Qt.Horizontal
            snapMode: ListView.SnapToItem
            interactive: false
            //model: 6
            //model: taskbarModel
            model: appModel
            clip: true

            Layout.fillHeight: true
            Layout.fillWidth: true

            delegate: AppItem{
                id: appItemDelegate

                //required property string visibleName
                //required property string iconName

                //required property string windowName

                implicitWidth: appItemView.height
                implicitHeight: appItemView.height

                iconName: model.iconName ? model.iconName : "application-x-desktop"
                //iconName: "application-x-desktop"

                // Rectangle{
                //     anchors.fill: parent
                //     color: "transparent"
                //     border.width: 1
                //     border.color: "red"
                // }
                Text{
                    anchors.centerIn: parent

                    text: model.visibleName
                    //text: windowName

                    //text: model.windowIcon
                    //text: "dupa"
                }
            }

            moveDisplaced: Transition{
                NumberAnimation {
                    properties: "x, y"
                    duration: 300
                    easing.type: Easing.InOutQuad
                }
            }

        }
    }
}
