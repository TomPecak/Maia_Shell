import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Maia.Client

import "../FishUI" as FishUI

Item {
    id: rootItem

    implicitHeight: 25
    implicitWidth: 640

    property int iconSize: 16

    property int windowX: 0
    property int windowY: 0
    property int windowWidth: rootItem.implicitWidth
    property int windowHeight: rootItem.implicitHeight

    property url wallpaperUrl
    property bool darkMode: false
    property color textColor: rootItem.darkMode ? "#FFFFFF" : "#000000";
    property var fontSize: rootItem.height ? rootItem.height / 3 : 1

    MBackgroundHelper {
        id: bgHelper

        wallpaperSource: Qt.resolvedUrl(wallpaperUrl)

        windowX: rootItem.windowX
        windowY: rootItem.windowY
        windowWidth: rootItem.windowWidth
        windowHeight: rootItem.windowHeight

        onNewColor: (color, darkMode) => {
                        background.color = color
                        rootItem.darkMode = darkMode

                        console.log("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX  color = " + color)
                        console.log("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX  darkMode = " + darkMode)
                    }

        onDebugImageGenerated: function(imageSource) {
            console.log("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
            debugImage.source = imageSource
            debugImage.visible = (imageSource !== "")
        }

    }

    // Window{
    //     id: debugWindow
    //     y:50
    //     width: 1920
    //     height: 100
    //     visible: true
    //     color: "red"

    //     Image {
    //         id: debugImage
    //         x:0
    //         y:0
    //         //anchors.centerIn: parent
    //         width: parent.width * 0.8
    //         height: 100 // Wysokość orientacyjna, obrazek się dopasuje
    //         fillMode: Image.PreserveAspectFit
    //         visible: false

    //         // Dodajemy czerwoną ramkę, żebyś widział gdzie dokładnie jest ten fragment
    //         Rectangle {
    //             anchors.fill: parent
    //             color: "transparent"
    //             border.color: "red"
    //             border.width: 2
    //         }

    //         // Tekst informacyjny
    //         Text {
    //             anchors.bottom: parent.top
    //             anchors.horizontalCenter: parent.horizontalCenter
    //             text: "DEBUG: Analizowany fragment tapety"
    //             color: "red"
    //             font.bold: true
    //         }
    //     }
    // }

    Rectangle {
        id: background
        anchors.fill: parent
        opacity: 0.3

        //color: "#000000"
        //color: "#4D4D4D"
        //color: "#64646E" //too dark
        // color: "#888888" // too dark
        color: "#AAAAAA"
        //color: "#E6E6E6" // too bright
        //color: "#FFFFFF" // too bright

        //        color: FishUI.Theme.darkMode ? "#4D4D4D" : "#FFFFFF"
        //        opacity: windowHelper.compositing ? FishUI.Theme.darkMode ? 0.5 : 0.7 : 1.0

        //        Behavior on color {
        //            ColorAnimation {
        //                duration: 100
        //                easing.type: Easing.Linear
        //            }
        //        }

        Component.onCompleted: {
            console.log("[WARNING] background color is not the same as in cutefishos, this need more research how to set proper backroung color")
        }
    }

    FishUI.DesktopMenu {
        id: acticityMenu

        MenuItem {
            text: qsTr("Close")
            //onTriggered: acticity.close()
        }
    }

    MActivity{
        id: acticity
    }

    // Main layout
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: FishUI.Units.smallSpacing
        anchors.rightMargin: FishUI.Units.smallSpacing
        spacing: FishUI.Units.smallSpacing / 2
        Layout.preferredWidth: Math.min(rootItem.width / 3,
                                        acticityLayout.implicitWidth + FishUI.Units.largeSpacing)

        // App name
        StandardItem {
            id: acticityItem
            animationEnabled: true
            Layout.fillHeight: true
            Layout.preferredWidth: Math.min(rootItem.width / 3,
                                            acticityLayout.implicitWidth + FishUI.Units.largeSpacing)
            onClicked: {
                if (mouse.button === Qt.RightButton)
                    acticityMenu.open()
            }


            RowLayout {
                id: acticityLayout
                anchors.fill: parent
                anchors.leftMargin: FishUI.Units.smallSpacing
                anchors.rightMargin: FishUI.Units.smallSpacing
                spacing: FishUI.Units.smallSpacing

                Image {
                    id: acticityIcon
                    width: rootItem.iconSize
                    height: rootItem.iconSize
                    sourceSize: Qt.size(rootItem.iconSize,
                                        rootItem.iconSize)
                    source: acticity.icon ? "image://icontheme/" + acticity.icon : ""
                    //source: Qt.resolvedUrl("../assets/images/system-search-symbolic.svg")
                    visible: status === Image.Ready
                    antialiasing: true
                    smooth: false
                }

                Label {
                    id: acticityLabel
                    text: acticity.title
                    Layout.fillWidth: true
                    elide: Qt.ElideRight
                    color: rootItem.textColor
                    visible: text
                    Layout.alignment: Qt.AlignVCenter
                    font.pointSize: rootItem.fontSize

                }
            }


            // Pop-up notification center and calendar
            StandardItem {
                id: datetimeItem

                animationEnabled: true
                Layout.fillHeight: true
                Layout.preferredWidth: _dateTimeLayout.implicitWidth + FishUI.Units.smallSpacing

                onClicked: {
                    //process.startDetached("cutefish-notificationd", ["-s"])
                }

                RowLayout {
                    id: _dateTimeLayout
                    anchors.fill: parent

                    //                Image {
                    //                    width: rootItem.iconSize
                    //                    height: width
                    //                    sourceSize: Qt.size(width, height)
                    //                    source: "qrc:/images/" + (rootItem.darkMode ? "dark/" : "light/") + "notification-symbolic.svg"
                    //                    asynchronous: true
                    //                    Layout.alignment: Qt.AlignCenter
                    //                    antialiasing: true
                    //                    smooth: false
                    //                }

                    Label {
                        id: timeLabel
                        Layout.alignment: Qt.AlignCenter
                        font.pointSize: rootItem.fontSize
                        color: rootItem.textColor

                        Timer {
                            id: timeTimer
                            interval: 1000
                            repeat: true
                            running: true
                            triggeredOnStart: true
                            onTriggered: {
                            }

                        }
                    }
                }
            }

        }

        // App menu
        Item {
            id: appMenuItem
            Layout.fillHeight: true
            Layout.fillWidth: true
        }

    }
}




























