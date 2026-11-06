import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import XPLunaFrontend
import Maia.Backend

Image {
    id: wallpaper
    anchors.fill: parent
    source: Qt.resolvedUrl("../../assets/images/images/xp_fhd.jpg")

    signal leftMouseButtonClicked()
    // The desktop menu opens at this point (desktop/DesktopMenuWindow.qml)
    signal rightMouseButtonClicked(real x, real y)

    // Button{
    //     anchors.centerIn: parent
    //     text: "Logout"
    //     onClicked: {
    //         console.log("logout clicked")
    //         MSessionManager.logout()
    //     }
    // }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.LeftButton
        onClicked: (mouse)=> {
                       if (mouse.button === Qt.RightButton) {
                           console.log("Wallpaper Right clicked 1 !!")
                           wallpaper.rightMouseButtonClicked(mouse.x, mouse.y)
                       }
                       if (mouse.button === Qt.LeftButton) {
                           console.log("Wallpaper Left clicked 1 !!")
                           wallpaper.leftMouseButtonClicked()
                       }
                   }
    }


    // MouseArea {
    //     anchors.fill: parent
    //     acceptedButtons: Qt.LeftButton | Qt.RightButton

    //     onClicked: (mouse) => {

    //                    if (mouse.button === Qt.RightButton) {
    //                        wallpaperContextMenu.popup(mouse.x, mouse.y)
    //                    }
    //                }
    // }





    // ListView {
    //     id: frontendListView
    //     anchors.centerIn: parent
    //     width: 300
    //     height: 300
    //     model: frontendManager
    //     clip: true

    //     delegate: ItemDelegate {
    //         width: parent.width
    //         height: 120

    //         Rectangle {
    //             anchors.fill: parent
    //             color: frontendActive ? "lightgreen" : "white"
    //             border.color: "#ddd"
    //             radius: 5

    //             ColumnLayout {
    //                 anchors.fill: parent
    //                 anchors.margins: 10
    //                 spacing: 5

    //                 Label {
    //                     text: "Name: " + frontendName
    //                     font.bold: true
    //                 }
    //                 Label {
    //                     text: "ID: " + frontendId
    //                 }
    //                 Label {
    //                     text: "Description: " + frontendDescription
    //                 }
    //                 Label {
    //                     text: "Path: " + frontendPath
    //                     font.italic: true
    //                 }
    //             }

    //             MouseArea {
    //                 anchors.fill: parent
    //                 onClicked: {
    //                     frontendManager.switchFrontend(frontendId)
    //                 }
    //             }
    //         }
    //     }

    //     ScrollBar.vertical: ScrollBar {}
    // }


    Column{
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 15
        spacing: 7

        Rectangle{
            id: cpuLoadBackground
            width: 150
            height: 37
            color: "#dd000000"
            Text{
                id: cpuLoad
                anchors.centerIn: parent
                text: "CPU: " + backend.cpuLoad.toFixed(1) + "%"
                font.pixelSize: 24
                color: "white"

                Component.onCompleted: {
                    backend.measureCpuLoad = true
                }
            }
        }

        Rectangle{
            id: qtVersionBackground
            width: 150
            height: 37
            color: "#dd000000"
            Text{
                anchors.centerIn: parent
                text: "Qt: " + backend.qtVersion
                font.pixelSize: 24
                color: "white"
            }

        }

        Rectangle{
            id: dpiBackground
            width: 150
            height: 37
            color: "#dd000000"
            Text{
                anchors.centerIn: parent
                text: "DPI: " + (Screen.pixelDensity * 25.4).toFixed(2)
                font.pixelSize: 24
                color: "white"
            }

        }
    }

}


