import QtQuick

// "Log off Windows" dialog: fullscreen transparent window with the XP dialog, shown from the start menu

Window{
    id: logOffDialog

    color: "transparent"
    visibility: Window.Hidden

    LogoutContent{
        anchors.fill: parent
        visible: logOffDialog.visible
        onCancelClicked: {
            logOffDialog.visibility = Window.Hidden
        }
    }
}
