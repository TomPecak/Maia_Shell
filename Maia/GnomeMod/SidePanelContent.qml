import QtQuick
import QtQuick.Controls
import Maia.Client

import "./style"

Rectangle{
    id: root
    implicitHeight: 600
    implicitWidth: 66
    //color: "#B2000000"
    color: "#C0131313"


    signal launcherButtonClicked()

    MFavoritesAppsModel{
        id: favoriteAppsModel
    }

    GMenu{
        id: favContextMenu

        width: 194

        property string app_id

        popupType: Popup.Native

        GMenuItem{
            active: false
            text: qsTr("New Window")
        }

        GMenuSeparator{
        }

        GMenuItem{
            text: qsTr("Unpin")
            onTriggered: {
                favoriteAppsModel.removeFavorite(favContextMenu.app_id)
            }

        }

        GMenuSeparator{
        }

        GMenuItem{
            active: false
            text: qsTr("App Details")
        }

        function showMenu(id){
            favContextMenu.app_id = id
            popup()
        }
    }

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.topMargin: 6
        anchors.bottom: allProgramsButton.top
        spacing: 3

        Repeater {
            id: favoritesRepeater
            model: favoriteAppsModel

            delegate: Control {
                id: button
                width: parent.width
                height: width
                //hoverEnabled: true

                // icon.source: "image://backend_app_icon/" + model.appIcon
                // icon.width: 48
                // icon.height: 48

                Image{
                    anchors.centerIn: parent

                    source: "image://backend_app_icon/" + model.appIcon

                    width: 48
                    height: 48
                    sourceSize.height: 48
                    sourceSize.width: 48
                }

                background: Rectangle{
                    anchors.fill: parent
                    color: button.hovered ? (button.down ? "#3cffffff" : "#1cffffff") : ("#00000000")
                    border.width: 0
                    radius: 12

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                MouseArea{
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse)=> {
                                   if (mouse.button === Qt.LeftButton){
                                       backend.runCommand(model.appExec)
                                   }
                               }
                    onPressed: (mouse)=> {
                                   if (mouse.button === Qt.RightButton){
                                       favContextMenu.showMenu(model.appId)
                                   }
                               }
                }

            }
        }

        Rectangle{ //separator beetween favoutite apps and taskbar
            height: 1
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.rightMargin: 6
            color: "#464646"
        }

        MTaskbarModel{
            id: taskbarModel
        }

        Repeater {
            id: taskBarRepeater
            model: taskbarModel

            delegate: Button {
                id: taskButton
                width: parent.width
                height: width
                hoverEnabled: true

                icon.source: model.windowIcon
                icon.width: 48
                icon.height: 48

                background: Rectangle{
                    anchors.fill: parent
                    color: taskButton.hovered ? (taskButton.down ? "#3cffffff" : "#1cffffff") : ("#00000000")
                    border.width: 0
                    radius: 12



                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                onClicked: {
                    backend.activateWindow(model.windowId)
                }

                // Text{
                //     anchors.centerIn: parent
                //     font.pointSize: 8
                //     color: "red"
                //     text: model.windowName
                // }

            }
        }
    }

    Button{
        id: allProgramsButton
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.left: parent.left
        anchors.leftMargin: 3
        height: allProgramsButton.width

        icon.source: "./images/launcher.svg"
        icon.height: allProgramsButton.height - 30
        icon.width: allProgramsButton.height - 30

        background: Rectangle{
            color: allProgramsButton.hovered ? (allProgramsButton.down ? "#3cffffff" : "#1cffffff") : ("#00000000")
            border.width: 0
            radius: 12

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }
        onClicked: {
            root.launcherButtonClicked();
        }
    }
}
