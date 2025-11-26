import QtQuick.Controls.Material
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Maia.Backend

import "../common_qml"
import "../style"
import ".."

Rectangle {
    id: root

    implicitWidth: 370
    //height: 327
    height: row_1.height + expandRect_1.height + row_2.height + row_2.anchors.topMargin + row_3.height + row_3.anchors.topMargin + row_4.height + row_4.anchors.topMargin + row_5.height + row_5.anchors.topMargin + row_6.height + row_6.anchors.topMargin + 2*19

    color: "#FFFFFF"
    radius: 14
    border.width: 1
    border.color: "#dedede"

    //Material.primary: "#03a9f4"
    //Material.primary: "green"
    // //Material.accent: "#03a9f4"
    Material.accent: UIStyle.accentColor
    // //Material.background: "#ffffff"
    // Material.accent: "#0073e5" //slider
    // Material.background: "blue"
    // Material.foreground:  "#3d3d3d" //text

    states: [
        State{
            name: "normal"
            PropertyChanges {
                target: expandRect_1
                height: 0
            }
        },
        State{
            name: "expanded"
            PropertyChanges {
                target: expandRect_1
                height: 297
            }
        }
    ]

    state: "normal"


    // Rectangle{
    //     x: 19
    //     y:19
    //     width: 370 - 2*19
    //     height: 327 - 2*19
    //     color: "lightpink"
    // }

    Item {
        id: row_1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.topMargin: 19
        anchors.rightMargin: 19
        height : 37

        //color: "#55546234"

        Button{
            text: "100%"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height + 12
            width: 86
            enabled: false
            leftPadding:0
            rightPadding: 0
            icon.source: "../icons/battery-level-100-symbolic.svg"
            icon.color: enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
            icon.width: 15
            icon.height: 15
            Component.onCompleted: {
                background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                if(enabled){
                    contentItem.color = UIStyle.colorButtonBatteryLevelIcon
                }else{
                    contentItem.color =  UIStyle.disabledTextColor
                }
                contentItem.font.pointSize = UIStyle.pointSizeControlBoardFont
                contentItem.font.family = UIStyle.familyControlBoardFont
            }
        }

        Row{
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -6
            spacing: 12

            Button {
                icon.source: "../icons/screenshot-app-symbolic.svg"
                icon.color: enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                icon.width: 15
                icon.height: 15
                leftPadding:0
                rightPadding: 0
                enabled: false
                height: parent.height + 12
                width: height - 12
                anchors.verticalCenter: parent.verticalCenter
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                }
            }

            Button {
                icon.source: "../icons/system-settings-symbolic.svg"
                icon.color: enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                icon.width: 15
                icon.height: 15
                leftPadding:0
                rightPadding: 0
                enabled: false
                height: parent.height + 12
                width: height - 12
                anchors.verticalCenter: parent.verticalCenter
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                }
            }

            Button {
                icon.source: "../icons/system-lock-screen-symbolic.svg"
                icon.color: enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                icon.width: 15
                icon.height: 15
                leftPadding:0
                rightPadding: 0
                height: parent.height + 12
                width: height - 12
                enabled: false
                anchors.verticalCenter: parent.verticalCenter
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                }
            }

            Button {
                icon.source: "../icons/system-shutdown-symbolic.svg"
                icon.color: UIStyle.colorButtonPowerIcon
                icon.width: 15
                icon.height: 15
                leftPadding:0
                rightPadding: 0
                height: parent.height + 12
                width: height - 12
                anchors.verticalCenter: parent.verticalCenter
                Component.onCompleted: {
                    background.color = UIStyle.colorButtonPower
                }

                onClicked: {
                    console.log("Power clicked")
                    root.state = (root.state === "normal") ? "expanded" : "normal"
                }
            }
        }
    }

    Item {
        id: expandRect_1
        anchors.top: row_1.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        //color: "lightskyblue"

        property int targetHeight: 297

        Behavior on height{
            NumberAnimation{
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }

        onHeightChanged: {
            if (height >= (targetHeight * 0.8))   // 80 % – dowolny próg
                sessionPopupRect.visible = true
            else
                sessionPopupRect.visible = false
        }


        Rectangle{
            id: sessionPopupRect
            anchors.centerIn: parent
            width: 334
            //height: 280
            height: expandRect_1.height - 17
            visible: false
            radius: 17
            border.width: 1
            border.color: "#d4d4d4"
            //border.color: "black"

            Item{
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                anchors.topMargin: 12
                //color: "lightgreen"
                Item{
                    id: headerRect
                    height: 50
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    //color: "red"
                    Item{
                        id: powerImgItem
                        height: parent.height
                        width: height
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom


                        Image{
                            id: powerImg
                            width: parent.width*0.7
                            height: width
                            anchors.centerIn: parent

                            source: "../icons/system-shutdown-symbolic.svg"
                            sourceSize: Qt.size(width,height)
                        }
                    }
                    Text{
                        text: "Power Off"
                        anchors.left: powerImgItem.right
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        color: UIStyle.colorControlBoardIcon

                        verticalAlignment: Text.AlignVCenter

                        font.pointSize: 14
                    }
                }
                ColumnLayout{
                    anchors.top: headerRect.bottom
                    anchors.right: parent.right
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 0

                    GMenuItem{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 37
                        text: "Suspend"
                        active: false
                    }
                    GMenuItem{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 37
                        text: "Restart..."
                        onTriggered: {
                            MSessionManager.reboot()
                        }
                    }
                    GMenuItem{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 37
                        text: qsTr("Power Off...")
                        onTriggered: {
                            MSessionManager.poweroff()
                        }
                    }
                    GMenuSeparator{
                        Layout.fillWidth: true
                    }
                    GMenuItem{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 37
                        text: qsTr("Log out...")
                        onTriggered: {
                            MSessionManager.logout()
                        }
                    }
                    GMenuItem{
                        Layout.fillWidth: true
                        Layout.preferredHeight: 37
                        text: qsTr("Switch User...")
                        onTriggered: {
                            MSessionManager.logout()
                        }
                    }
                }
            }


        }

    }

    Item {
        id: row_2
        height : 37
        anchors.top: expandRect_1.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        anchors.topMargin: 9

        //color: "#55889900"
        RoundButton{
            id: spekaerButton
            height: parent.height + 5
            width: height
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: -6
            icon.source: "../icons/audio-volume-high-symbolic.svg"
            icon.color: UIStyle.colorControlBoardIcon
            display: AbstractButton.IconOnly

            background: Rectangle{
                radius: spekaerButton.height/2
                color: spekaerButton.hovered ? "#e8e8e8" : "#FFFFFF"
            }
        }

        Slider{
            from: 0
            value: (audioBackend.prefferedOutputVolume / audioBackend.normalVolume * 100)
            to: 100
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: spekaerButton.right
            onMoved: {
                audioBackend.prefferedOutputVolume = value * audioBackend.normalVolume / 100
            }
        }

    }

    Rectangle {
        id: row_3
        height : 37
        anchors.top: row_2.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        anchors.topMargin: 5


        //color: "#55881100"
        RoundButton{
            id: brightness
            height: parent.height + 5
            width: height
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: -6
            enabled: false
            icon.source: "../icons/display-brightness-symbolic.svg"
            icon.color: enabled ? UIStyle.colorControlBoardIcon : UIStyle.disabledTextColor
            display: AbstractButton.IconOnly

            background: Rectangle{
                radius: brightness.height/2
                color: brightness.hovered ? "#e8e8e8" : "#FFFFFF"
            }
        }

        Slider{
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: brightness.right
            enabled: false
        }
    }

    // Rectangle {
    //     //Layout.preferredHeight: 1
    //     Layout.minimumHeight: 1
    //     Layout.fillHeight: true
    //     Layout.fillWidth: true
    //     Layout.topMargin: 0
    //     Layout.bottomMargin: 0
    //     color: "lightskyblue"
    // }

    Rectangle {
        id: row_4
        height : 44
        anchors.top: row_3.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        anchors.topMargin: 8

        //color: "#558800BB"
        Row{
            anchors.fill: parent
            spacing: 12
            ActionButton{
                width: 160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                leftText: "Wi-Fi"
                leftIconSource: "../images/network-wireless-connected-symbolic.svg"
                enabled: false
                active: false
                iconColorActive: UIStyle.colorControlBoardIconActive
                iconColorInactive: UIStyle.colorControlBoardIcon
                disabledTextColor: UIStyle.disabledTextColor
                disabledBackgroundColor: UIStyle.disabledButtonColor
            }

            // Button{
            //     width: 160
            //     height: parent.height + 12
            //     anchors.verticalCenter: parent.verticalCenter
            // }
            ActionButton{
                width:160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                leftText: "Bluetooth"
                leftIconSource: "../icons/bluetooth-active-symbolic.svg"
                active: false
                enabled: false
                iconColorActive: UIStyle.colorControlBoardIconActive
                iconColorInactive: UIStyle.colorControlBoardIcon
                disabledTextColor: UIStyle.disabledTextColor
                disabledBackgroundColor: UIStyle.disabledButtonColor
            }
        }
    }
    Rectangle {
        id: row_5
        height : 44
        anchors.top: row_4.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        anchors.topMargin: 12

        //color: "#55149900"
        Row{
            anchors.fill: parent
            spacing: 12
            ActionButton{
                width: 160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                leftText: qsTr("Power Profile")
                leftIconSource: "../images/network-wireless-connected-symbolic.svg"
                enabled: false
                active: false
                iconColorActive: UIStyle.colorControlBoardIconActive
                iconColorInactive: UIStyle.colorControlBoardIcon
                disabledTextColor: UIStyle.disabledTextColor
                disabledBackgroundColor: UIStyle.disabledButtonColor
            }
            Button{
                width:160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Night Mode")
                enabled: false
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                    contentItem.color = enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                    contentItem.font.pointSize = UIStyle.pointSizeControlBoardFont
                    contentItem.font.family = UIStyle.familyControlBoardFont
                }
            }
        }
    }
    Rectangle {
        id: row_6
        height : 44
        anchors.top: row_5.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 19
        anchors.rightMargin: 19
        anchors.topMargin: 12

        //color: "#55881155"
        Row{
            anchors.fill: parent
            spacing: 12
            Button{
                width: 160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Dark Style")
                enabled: false
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                    contentItem.color = enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                    contentItem.font.pointSize = UIStyle.pointSizeControlBoardFont
                    contentItem.font.family = UIStyle.familyControlBoardFont
                }
            }
            Button{
                width:160
                height: parent.height + 12
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Airplane Mode")
                enabled: false
                Component.onCompleted: {
                    background.color = enabled ? UIStyle.colorButtonBatteryLevel : UIStyle.disabledButtonColor
                    contentItem.color = enabled ? UIStyle.colorButtonBatteryLevelIcon : UIStyle.disabledTextColor
                    contentItem.font.pointSize = UIStyle.pointSizeControlBoardFont
                    contentItem.font.family = UIStyle.familyControlBoardFont
                }
            }
        }
    }



}
