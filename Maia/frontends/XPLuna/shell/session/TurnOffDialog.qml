import QtQuick

// "Turn off computer" dialog: fullscreen transparent window with the XP dialog, shown from the start menu

Window{
    id: turnOffDialog

    color: "transparent"
    visibility: Window.Hidden

    TurnOffContent{
        anchors.fill: parent
        visible: turnOffDialog.visible
        onCancelClicked: {
            turnOffDialog.visibility = Window.Hidden
        }
    }
}
