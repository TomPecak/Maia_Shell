import QtQuick
import Maia.Windows as Windows

Image {
    id: panel
    height: 30
    // Resolved from this file: a relative URL on the root object of a component would be resolved
    // from the file that creates it (shell/Main.qml)
    source: Qt.resolvedUrl("../../assets/images/task_bar_background.bmp")
    property bool inputMenuVisible: false

    signal startPressed()
    signal endPressed()
    // The speaker of the notification area was clicked (the volume slider)
    signal volumeClicked()

    onInputMenuVisibleChanged: {
        if(inputMenuVisible === false){
            if(!startButtonMouseArea.containsMouse){
                startImage.source = "../../assets/images/images/start_normal.bmp";
            }
        }
    }


    Image {
        id: startImage
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: parent.height
        width: 101
        source: "../../assets/images/images/start_normal.bmp"
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
                    startImage.source = "../../assets/images/images/start_pressed.bmp";
                }else{
                    startImage.source = "../../assets/images/images/start_hover.bmp";
                }
            }
            onExited: {
                if(inputMenuVisible){
                    startImage.source = "../../assets/images/images/start_pressed.bmp";
                }else{
                    startImage.source = "../../assets/images/images/start_normal.bmp";
                }
            }
            onPressed: {
                panel.startPressed()

                if(inputMenuVisible){
                    startImage.source = "../../assets/images/images/start_pressed.bmp";
                }else{
                    if (containsMouse) {
                        startImage.source = "../../assets/images/images/start_hover.bmp";
                    } else {
                        startImage.source = "../../assets/images/images/start_normal.bmp";
                    }
                }
            }
            onReleased: {
                panel.endPressed()

                if(inputMenuVisible){
                    startImage.source = "../../assets/images/images/start_pressed.bmp";
                }else{
                    if (containsMouse) {
                        startImage.source = "../../assets/images/images/start_hover.bmp";
                    } else {
                        startImage.source = "../../assets/images/images/start_normal.bmp";
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

        // One button per window, in the order they were opened. The Maia window service talks
        // to KWin; the X11 window list of the old model does not exist on Wayland.
        Windows.TasksModel {
            id: taskbarModel

            groupMode: Windows.TasksModel.GroupDisabled
            sortMode: Windows.TasksModel.SortManual
        }

        Repeater {
            id: taskbarRepeater

            model: taskbarModel

            TaskbarButton{
                id: taskButtonNormal

                minimumWidth: taskbarRow.elementMinimumWidth
                minimumHeight: 25

                text: model.display
                source: model.decoration

                width: taskbarRow.elementWidth
                height: 25

                property bool activeWindow : model.IsActive === true

                //works good with onRelease
                buttonState: activeWindow ? (buttonMouseArea.containsMouse ? (buttonMouseArea.pressed ? TaskbarButton.ButtonState.Pressed :  TaskbarButton.ButtonState.PressedHover) /* containsMouse = false */: (TaskbarButton.ButtonState.Pressed)) /*activeWindow = false*/: (buttonMouseArea.containsMouse ? (buttonMouseArea.pressed?  TaskbarButton.ButtonState.Pressed : TaskbarButton.ButtonState.NormalHover) /* containsMouse = false */ : (TaskbarButton.ButtonState.Normal))

                MouseArea {
                    id: buttonMouseArea
                    anchors.fill: parent
                    hoverEnabled: true

                    // As in Windows XP: the active window's button minimizes it, another one
                    // activates its window. The taskbar takes no keyboard focus (layer shell,
                    // no keyboard interactivity), so the active window stays active.
                    onReleased: {
                        const taskIndex = taskbarModel.makeModelIndex(index)
                        if (taskButtonNormal.activeWindow)
                            taskbarModel.requestToggleMinimized(taskIndex)
                        else
                            taskbarModel.requestActivate(taskIndex)
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
        source: "../../assets/images/taskpanel_separator.bmp"
        fillMode: Image.TileHorizontally
    }

    Image{
        id: notificationAreaBackground
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height
        width: 104
        source: "../../assets/images/clock_background.bmp"
        fillMode: Image.TileHorizontally

        Image{
            id: speakerButton
            anchors.right: dateTimeDisplay.left
            anchors.rightMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            width:16
            height:16
            source: "../../assets/images/taskbar/notification_area/speaker.bmp"
            fillMode: Image.Stretch

            MouseArea{
                anchors.fill: parent
                onClicked: panel.volumeClicked()
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
