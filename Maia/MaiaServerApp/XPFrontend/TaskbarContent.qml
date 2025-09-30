import QtQuick
import Maia.Client

Image {
    id: panel
    height: 30
    source: "qrc:/assets/images/task_bar_background.bmp"
    property bool inputMenuVisible: false

    signal startPressed()
    signal endPressed()

    onInputMenuVisibleChanged: {
        if(inputMenuVisible === false){
            if(!startButtonMouseArea.containsMouse){
                startImage.source = "qrc:/assets/images/images/start_normal.bmp";
            }
        }
    }


    Image {
        id: startImage
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: parent.height
        width: 101
        source: "qrc:/assets/images/images/start_normal.bmp"
        fillMode: Image.TileHorizontally // or another option depending on the requirements.

        Component.onCompleted: {
            console.log("WARNING TODO: It seems that a more optimal solution, instead of replacing the source for the Image, would be to create three Image elements and switch between them")
        }

        MouseArea {
            id: startButtonMouseArea
            anchors.fill: parent
            hoverEnabled: true



            onEntered: {
                if(inputMenuVisible){
                    startImage.source = "qrc:/assets/images/images/start_pressed.bmp";
                }else{
                    startImage.source = "qrc:/assets/images/images/start_hover.bmp";
                }
            }
            onExited: {
                if(inputMenuVisible){
                    startImage.source = "qrc:/assets/images/images/start_pressed.bmp";
                }else{
                    startImage.source = "qrc:/assets/images/images/start_normal.bmp";
                }
            }
            onPressed: {
                panel.startPressed()

                if(inputMenuVisible){
                    //backend.minimalizeAllWindows()
                    startImage.source = "qrc:/assets/images/images/start_pressed.bmp";
                }else{
                    if (containsMouse) {
                        startImage.source = "qrc:/assets/images/images/start_hover.bmp";
                    } else {
                        startImage.source = "qrc:/assets/images/images/start_normal.bmp";
                    }
                }
            }
            onReleased: {
                panel.endPressed()

                if(inputMenuVisible){
                    startImage.source = "qrc:/assets/images/images/start_pressed.bmp";
                }else{
                    if (containsMouse) {
                        startImage.source = "qrc:/assets/images/images/start_hover.bmp";
                    } else {
                        startImage.source = "qrc:/assets/images/images/start_normal.bmp";
                    }
                }
            }
        }
    }

    Row {
        id: taskbarRow
        readonly property int elementMinimumWidth: 52
        readonly property int elementMaximumWidth: 160
        property int availableWidth: width
        property int elementWidth: Math.min(availableWidth / taskbarRepeater.count, elementMaximumWidth)

        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.bottom: parent.bottom
        anchors.left: startImage.right
        anchors.leftMargin: 5
        anchors.right: separator.left
        spacing: 0
        visible: true

        MTaskbarModel{
            id: taskbarModel
        }



        Repeater {
            id: taskbarRepeater

            model: taskbarModel

            TaskbarButton{
                id: taskButtonNormal

                minimumWidth: taskbarRow.elementMinimumWidth
                minimumHeight: 25

                text: model.windowName
                source: model.windowIcon

                width: taskbarRow.elementWidth
                height: 25

                property bool activeWindow : model.windowActive

                //works good with onRelease
                buttonState: activeWindow ? (buttonMouseArea.containsMouse ? (buttonMouseArea.pressed ? TaskbarButton.ButtonState.Pressed :  TaskbarButton.ButtonState.PressedHover) /* containsMouse = false */: (TaskbarButton.ButtonState.Pressed)) /*activeWindow = false*/: (buttonMouseArea.containsMouse ? (buttonMouseArea.pressed?  TaskbarButton.ButtonState.Pressed : TaskbarButton.ButtonState.NormalHover) /* containsMouse = false */ : (TaskbarButton.ButtonState.Normal))

                MouseArea {
                    id: buttonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true

                    // TODO: Here, there is a difference in behavior compared to Windows XP.
                    //       After pressing the button, the focus and active window are taken
                    //       over by the panel, which doesn’t happen in Windows XP. I’m not sure
                    //       how to fix this yet, so I’m leaving the implementation as it is for now.
                    onReleased: {
                        backend.activateWindow(model.windowId)
                    }
                }

            }
        }
    }

    Image{
        id: separator
        anchors.right: notificationAreaBackground.left
        anchors.bottom: notificationAreaBackground.bottom
        height: notificationAreaBackground.height
        width: 10
        source: "qrc:/assets/images/taskpanel_separator.bmp"
        fillMode: Image.TileHorizontally
    }

    Image{
        id: notificationAreaBackground
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height
        width: 104
        source: "qrc:/assets/images/clock_background.bmp"
        fillMode: Image.TileHorizontally

        Image{
            id: speakerButton
            anchors.right: dateTimeDisplay.left
            anchors.rightMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            width:16
            height:16
            source: "qrc:/assets/images/taskbar/notification_area/speaker.bmp"
            fillMode: Image.Stretch

            MouseArea{
                anchors.fill: parent
                onClicked: {
                    systemVolumeSlider.visible = true
                }
            }

        }


        Text {
            id: dateTimeDisplay
            anchors.right: parent.right
            anchors.rightMargin: 17
            anchors.verticalCenter: parent.verticalCenter
            color: "white"

            font.family: "Tahoma"
            font.styleName: "Regular"
            font.pointSize: 8.0
            font.kerning: true
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            antialiasing: false

            text: Qt.formatDateTime(new Date(), "hh:mm")
            //text: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")

            Timer {
                interval: 10000 // refresh each 10 sec
                running: true
                repeat: true
                onTriggered: {
                    //dateTimeDisplay.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
                    dateTimeDisplay.text = Qt.formatDateTime(new Date(), "hh:mm")
                }
            }
        }
    }
}
