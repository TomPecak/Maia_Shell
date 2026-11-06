import QtQuick
import org.kde.layershell 1.0 as LayerShell

// "Turn off computer": the XP dialog over the whole screen (the overlay layer, above everything,
// the taskbar too), with the keyboard to itself while it is shown.
//
// Open and close it with `visible`.
Window{
    id: turnOffDialog

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "xpluna-turnoff"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true

    Shortcut {
        sequence: "Escape"
        enabled: turnOffDialog.visible
        onActivated: turnOffDialog.visible = false
    }

    TurnOffContent{
        anchors.fill: parent
        visible: turnOffDialog.visible
        onCancelClicked: {
            turnOffDialog.visible = false
        }
    }
}
