import QtQuick
import QtQuick.Controls
import Maia.Client


Rectangle {
    id: root

    signal cancelClicked()

    color: "#00000000"

    Behavior on color {
        id: behaviorOnBackgroundColor
        ColorAnimation {
            duration: 5000
        }
    }

    onVisibleChanged: {
        if (visible === true) {
            behaviorOnBackgroundColor.enabled = true
            color = "#BB000000";
        } else {
            behaviorOnBackgroundColor.enabled = false
            color = "#00000000";
        }
    }

    Image{
        id: turnOffDialog
        anchors.centerIn: parent
        width: 314
        height: 200
        source: "./assets/images/images/log_off_dialog.bmp"


        Item{
            id: logOffButton
            x: 199
            y: 81
            width: logOffButtonImage.width
            height: logOffButtonImage.height

            Item{
                id: logOffButtonImage
                anchors.centerIn: parent
                width: 33
                height: 33
                Image{
                    id: logOffButtonNormal
                    width: 33
                    height: 33
                    visible: !logOffButtonMouseArea.pressed && !logOffButtonMouseArea.containsMouse
                    source: "./assets/images/images/dialog_log_off_logoff_button_normal.bmp"
                }
                Image{
                    id: logOffButtonHover
                    width: 33
                    height: 33
                    visible: !logOffButtonMouseArea.pressed && logOffButtonMouseArea.containsMouse
                    source: "./assets/images/images/dialog_log_off_logoff_button_hover.bmp"
                }
                Image{
                    id: logOffButtonPressed
                    width: 33
                    height: 33
                    visible: logOffButtonMouseArea.pressed
                    source: "./assets/images/images/dialog_log_off_logoff_button_pressed.bmp"
                }
                MouseArea{
                    id: logOffButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled : true
                    onClicked: {
                        MSessionManager.logout()
                    }
                }
            }

            Text{
                text: qsTr("Log Off")
                anchors.top: logOffButtonImage.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: logOffButtonImage.horizontalCenter

                color: "#FFFFFF"

                font.family: "Tahoma"
                font.weight: Font.Bold
                font.pointSize: 8.0
                font.kerning: true
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                antialiasing: false
            }
        }

        Item{
            id: switchUserButton
            x: 84
            y: 81
            width: switchUserButtonImage.width
            height: switchUserButtonImage.height

            Item{
                id: switchUserButtonImage
                anchors.centerIn: parent
                width: 33
                height: 33
                Image{
                    id: switchUserButtonNormal
                    width: 33
                    height: 33
                    visible: !switchUserButtonMouseArea.pressed
                    source: "./assets/images/images/dialog_log_off_switchuser_button_normal.bmp"
                }
                Image{
                    id: switchUserButtonPressed
                    width: 33
                    height: 33
                    visible: switchUserButtonMouseArea.pressed
                    source: "./assets/images/images/dialog_log_off_switchuser_button_pressed.bmp"
                }
                MouseArea{
                    id: switchUserButtonMouseArea
                    anchors.fill: parent
                    hoverEnabled : true
                    onClicked: {
                        MSessionManager.logout()
                    }
                }
            }

            Text{
                text: qsTr("Switch User")
                anchors.top: switchUserButtonImage.bottom
                anchors.topMargin: 6
                x: -17

                color: "#FFFFFF"

                font.family: "Tahoma"
                font.weight: Font.Bold
                font.pointSize: 8.0
                font.kerning: true
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                antialiasing: false
            }
        }


        Image{
            id: cancelButton
            x: 243
            y: 168
            width: 61
            height: 21
            source: "./assets/images/dialog_turn_off_cancel_button_normal.png"

            MouseArea{
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    if(!pressed)
                        cancelButton.source = "./assets/images/dialog_turn_off_cancel_button_hover.png"
                }
                onExited: {
                    if(!pressed)
                        cancelButton.source = "./assets/images/dialog_turn_off_cancel_button_normal.png"
                }
                onPressed: {
                    cancelButton.source = "./assets/images/dialog_turn_off_cancel_button_pressed.png"
                }
                onReleased: {
                    if(containsMouse){
                        cancelButton.source = "./assets/images/dialog_turn_off_cancel_button_hover.png"
                        root.cancelClicked()
                    }else{
                        cancelButton.source = "./assets/images/dialog_turn_off_cancel_button_normal.png"
                    }
                }
            }
        }
    }
}
