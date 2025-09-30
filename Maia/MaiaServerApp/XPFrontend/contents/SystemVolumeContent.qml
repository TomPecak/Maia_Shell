import QtQuick
import QtQuick.Controls
import "../style_items"

TiledImage{
    id: normalButtonImage

    width: 81
    height: 136

    visible: true

    leftTopSource: "qrc:/assets/images/system_volume_dialog/top_left.bmp"
    leftMiddleSource: "qrc:/assets/images/system_volume_dialog/middle_left.bmp"
    leftBottomSource: "qrc:/assets/images/system_volume_dialog/bottom_left.bmp"

    middleTopSource: "qrc:/assets/images/system_volume_dialog/top_middle.bmp"
    middleMiddleSource: "qrc:/assets/images/system_volume_dialog/middle_middle.bmp"
    middleBottomSource: "qrc:/assets/images/system_volume_dialog/bottom_middle.bmp"

    rightTopSource: "qrc:/assets/images/system_volume_dialog/top_right.bmp"
    rightMiddleSource: "qrc:/assets/images/system_volume_dialog/middle_right.bmp"
    rightBottomSource: "qrc:/assets/images/system_volume_dialog/bottom_right.bmp"

    Text{
        id: volumeText
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter

        font.family: "Tahoma"
        font.styleName: "Regular"
        font.pointSize: 8.0
        font.kerning: true
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
        antialiasing: false

        text: qsTr("Volume")
    }

    Slider{
        id: control
        orientation: Qt.Vertical

        anchors.top: volumeText.bottom
        anchors.topMargin: 12
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: muteItem.top
        anchors.bottomMargin: 17

        from: 0
        value: (audioBackend.prefferedOutputVolume / audioBackend.normalVolume * 100)
        to: 100


        onMoved: {
            audioBackend.prefferedOutputVolume = value * audioBackend.normalVolume / 100
        }

        background: TiledImageVertical {
            x: control.orientation === Qt.Horizontal ? (control.leftPadding) : (control.leftPadding + control.availableWidth / 2 - width/2)
            y: control.orientation === Qt.Horizontal ? (control.topPadding + control.availableHeight / 2 - height / 2) : control.topPadding
            implicitWidth: control.orientation === Qt.Horizontal ? (200) : (4)
            implicitHeight: control.orientation === Qt.Horizontal ? (4) : (200)
            width: control.orientation === Qt.Horizontal ? (control.availableWidth) : implicitWidth
            height: control.orientation === Qt.Horizontal ? (implicitHeight) : (control.availableHeight)
            topSource: "qrc:/assets/images/system_volume_dialog/slider/slider_background_top.bmp"
            middleSource: "qrc:/assets/images/system_volume_dialog/slider/slider_background_middle.bmp"
            bottomSource: "qrc:/assets/images/system_volume_dialog/slider/slider_background_bottom.bmp"
        }


        handle: Image {
            id: customHandle
            x: control.orientation === Qt.Horizontal ? (control.leftPadding + control.visualPosition * (control.availableWidth - width)) : (control.leftPadding + control.availableWidth / 2 - width / 2)
            y: control.orientation === Qt.Horizontal ? (control.topPadding + control.availableHeight / 2 - height / 2) : (control.topPadding + control.visualPosition * (control.availableHeight - height))
            width: 22
            height: 11

            source: "qrc:/assets/images/system_volume_dialog/slider/slider_handle_normal.bmp"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                propagateComposedEvents: true

                onEntered: {
                    console.log("onEntered()")
                    customHandle.source = "qrc:/assets/images/system_volume_dialog/slider/slider_handle_hover.bmp";
                }

                onExited: {
                    console.log("onExited()")

                    customHandle.source = "qrc:/assets/images/system_volume_dialog/slider/slider_handle_normal.bmp";

                }

                onPressed: (mouse) => {
                    console.log("onPressed()")
                    customHandle.source = "qrc:/assets/images/system_volume_dialog/slider/slider_handle_pressed.bmp";
                    mouse.accepted = false; // Pozwala przesuwać suwak
                }

                onReleased: (mouse) => {
                    console.log("onRelease()")

                    customHandle.source = (containsMouse)
                    ? "qrc:/assets/images/system_volume_dialog/slider/slider_handle_hover.bmp"
                    : "qrc:/assets/images/system_volume_dialog/slider/slider_handle_normal.bmp";
                    mouse.accepted = false; // Pozwala przesuwać suwak
                }
            }
        }

    }

    Item{
        id: muteItem
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        height: muteCheckboxImage.height
        // Rectangle{
        //     anchors.fill: parent
        //     color: "red"
        // }

        MouseArea {
            id: muteMouseArea
            anchors.fill: parent
            hoverEnabled: true

            onClicked: {
                audioBackend.prefferedOutputMuted = !audioBackend.prefferedOutputMuted;
            }
        }

        Image {
            id: muteCheckboxImage
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.bottom: parent.bottom
            height: 13
            width: 13

            // Dynamiczne przypisanie źródła obrazu
            source: {
                if (muteMouseArea.pressed) {
                    return audioBackend.prefferedOutputMuted
                        ? "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_pressed_checked.bmp"
                        : "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_pressed.bmp";
                } else if (muteMouseArea.containsMouse) {
                    return audioBackend.prefferedOutputMuted
                        ? "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_hover_checked.bmp"
                        : "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_hover.bmp";
                } else {
                    return audioBackend.prefferedOutputMuted
                        ? "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_normal_checked.bmp"
                        : "qrc:/assets/images/system_volume_dialog/mute_checkbox/mute_normal.bmp";
                }
            }
        }

        Text{
            id: muteText
            anchors.left: muteCheckboxImage.right
            anchors.leftMargin: 3
            anchors.bottom: muteCheckboxImage.bottom

            font.family: "Tahoma"
            font.styleName: "Regular"
            font.pointSize: 8.0
            font.kerning: true
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            antialiasing: false

            text: qsTr("Mute")
            // Rectangle{
            //     anchors.fill: parent
            //     color: "#4400FF00"
            // }
        }
        // CheckBox{
        //     id: helperMuteCheckBox
        //     height: 13
        //     width: 13
        //     anchors.left: muteText.right
        //     anchors.bottom: muteText.bottom
        //     checked: audioBackend.prefferedOutputMuted
        //     onCheckedChanged: {
        //         audioBackend.prefferedOutputMuted = helperMuteCheckBox.checked
        //     }
        // }

    }




}
