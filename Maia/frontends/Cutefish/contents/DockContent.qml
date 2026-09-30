import QtQuick
import QtQuick.Layouts

import Maia.Backend

import "../items"
import "../popups"

Item {
    id: root
    property bool darkMode: false


    property bool isHorizontal: true
    property real windowRadius: 0.3 * height

    signal appsItemClicked(var mouse)

    MTaskbarModel{
        id: taskbarModel
    }

    ApplicationModel{
        id: appModel
    }


    implicitHeight: 56
    implicitWidth: implicitHeight
    width: appItemView.count * root.height + launcherItem.width


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
        id: grid
        anchors.fill: parent
        anchors.topMargin: 0
        flow: Grid.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        DockItem{
            id: launcherItem
            implicitWidth: isHorizontal ? root.height : root.width
            implicitHeight: isHorizontal ? root.height : root.width
            popupText: qsTr("Apps")
            enableActivateDot: false
            //iconName: "application-x-desktop"
            //iconName: "user-trash-empty"
            //iconName: "launcher"
            //iconName: "launcher.svg"
            //iconName: "../assets/images/launcher.svg"
            iconName: Qt.resolvedUrl("../assets/images/launcher.svg")
            onClicked: {
                root.appsItemClicked(mouse)
            }

        }

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

                isActive: model.isActive
                iconName: model.iconName ? model.iconName : "application-x-desktop"
                popupText: model.visibleName

                // Rectangle{
                //     anchors.fill: parent
                //     color: "transparent"
                //     border.width: 1
                //     border.color: "red"
                // }
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
























































