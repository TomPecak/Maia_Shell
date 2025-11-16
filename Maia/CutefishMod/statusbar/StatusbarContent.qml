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

    property bool darkMode: false
    property color textColor: rootItem.darkMode ? "#000000" : "#FFFFFF";
        property var fontSize: rootItem.height ? rootItem.height / 3 : 1

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



        }

        // App menu
        Item {
            id: appMenuItem
            Layout.fillHeight: true
            Layout.fillWidth: true
        }

    }
}
