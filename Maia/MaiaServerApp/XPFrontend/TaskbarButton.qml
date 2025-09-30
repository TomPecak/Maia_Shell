import QtQuick

import "./style_items"

Item{

    property alias text: buttonText.text
    property alias source: icon.source
    property int minimumWidth: normalButtonImage.minimumWidth
    property int minimumHeight: normalButtonImage.minimumHeight

    enum ButtonState {
        Normal,
        NormalHover,
        Pressed,
        PressedHover
    }

    property int buttonState: TaskbarButton.ButtonState.Normal

    onHeightChanged: {
        if(height < minimumHeight){
            height = minimumHeight
        }
    }

    onWidthChanged: {
        if(width < minimumWidth){
            width = minimumWidth
        }
    }

    TiledImage{
        id: normalButtonImage
        width: parent.width
        height: parent.height
        visible: parent.buttonState === TaskbarButton.ButtonState.Normal

        leftTopSource: "qrc:/assets/images/taskbar/background_button_normal/top_left.png"
        leftMiddleSource: "qrc:/assets/images/taskbar/background_button_normal/middle_left.png"
        leftBottomSource: "qrc:/assets/images/taskbar/background_button_normal/bottom_left.png"

        middleTopSource: "qrc:/assets/images/taskbar/background_button_normal/top_middle.png"
        middleMiddleSource: "qrc:/assets/images/taskbar/background_button_normal/middle_middle.bmp"
        middleBottomSource: "qrc:/assets/images/taskbar/background_button_normal/bottom_middle.png"

        rightTopSource: "qrc:/assets/images/taskbar/background_button_normal/top_right.png"
        rightMiddleSource: "qrc:/assets/images/taskbar/background_button_normal/middle_right.png"
        rightBottomSource: "qrc:/assets/images/taskbar/background_button_normal/bottom_right.png"
    }

    TiledImage{
        id: hoverButtonImage
        width: parent.width
        height: parent.height
        visible: parent.buttonState === TaskbarButton.ButtonState.NormalHover

        leftTopSource: "qrc:/assets/images/taskbar/background_button_hover/left_top.bmp"
        leftMiddleSource: "qrc:/assets/images/taskbar/background_button_hover/left_middle.bmp"
        leftBottomSource: "qrc:/assets/images/taskbar/background_button_hover/left_bottom.bmp"

        middleTopSource: "qrc:/assets/images/taskbar/background_button_hover/middle_top.bmp"
        middleMiddleSource: "qrc:/assets/images/taskbar/background_button_hover/middle_middle.bmp"
        middleBottomSource: "qrc:/assets/images/taskbar/background_button_hover/middle_bottom.bmp"

        rightTopSource: "qrc:/assets/images/taskbar/background_button_hover/right_top.bmp"
        rightMiddleSource: "qrc:/assets/images/taskbar/background_button_hover/right_middle.bmp"
        rightBottomSource: "qrc:/assets/images/taskbar/background_button_hover/right_bottom.bmp"
    }

    TiledImage{
        id: pressedButtonImage
        width: parent.width
        height: parent.height
        visible: parent.buttonState === TaskbarButton.ButtonState.Pressed

        leftTopSource: "qrc:/assets/images/taskbar/background_button_pressed/left_top.bmp"
        leftMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed/left_middle.bmp"
        leftBottomSource: "qrc:/assets/images/taskbar/background_button_pressed/left_bottom.bmp"

        middleTopSource: "qrc:/assets/images/taskbar/background_button_pressed/middle_top.bmp"
        middleMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed/middle_middle.bmp"
        middleBottomSource: "qrc:/assets/images/taskbar/background_button_pressed/middle_bottom.bmp"

        rightTopSource: "qrc:/assets/images/taskbar/background_button_pressed/right_top.bmp"
        rightMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed/right_middle.bmp"
        rightBottomSource: "qrc:/assets/images/taskbar/background_button_pressed/right_bottom.bmp"
    }

    TiledImage{
        id: pressedHoverButtonImage
        width: parent.width
        height: parent.height
        visible: parent.buttonState === TaskbarButton.ButtonState.PressedHover

        leftTopSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/left_top.bmp"
        leftMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/left_middle.bmp"
        leftBottomSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/left_bottom.bmp"

        middleTopSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/middle_top.bmp"
        middleMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/middle_middle.bmp"
        middleBottomSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/middle_bottom.bmp"

        rightTopSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/right_top.bmp"
        rightMiddleSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/right_middle.bmp"
        rightBottomSource: "qrc:/assets/images/taskbar/background_button_pressed_hover/right_bottom.bmp"
    }

    Image{
        id: icon
        width: 16
        height: 16
        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.leftMargin: 10
        anchors.left: parent.left
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(width,height)
    }

    Text{
        id: buttonText
        anchors.left: icon.right
        anchors.leftMargin: 5
        anchors.verticalCenter : parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 10
        text: "My Computer"
        color: "white"

        font.family: "Tahoma"
        font.styleName: "Regular"
        font.pointSize: 8.0
        font.kerning: true
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
        antialiasing: false

        clip: true
    }
}
