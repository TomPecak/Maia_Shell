import QtQuick
import org.kde.layershell 1.0 as LayerShell

// "Log off Windows": the XP dialog over the whole screen (the overlay layer, above everything,
// the taskbar too), with the keyboard to itself while it is shown.
//
// Open and close it with `visible`.
Window{
    id: logOffDialog

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "xpluna-logoff"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.activateOnShow: true

    Shortcut {
        sequence: "Escape"
        enabled: logOffDialog.visible
        onActivated: logOffDialog.visible = false
    }

    LogoutContent{
        anchors.fill: parent
        visible: logOffDialog.visible
        onCancelClicked: {
            logOffDialog.visible = false
        }
    }
}
