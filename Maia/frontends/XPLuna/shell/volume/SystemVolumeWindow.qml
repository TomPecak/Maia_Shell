import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

// The volume slider above the speaker of the notification area: a layer-shell surface in the
// bottom right corner, above the taskbar (its exclusion zone). The slider sits `rightInset` from
// the screen edge; the window is wider by that much and only the slider takes input (MaskArea).
// Closes when it loses the keyboard focus or on Escape.
//
// Open and close it with `visible`.
Window {
    id: window

    property int rightInset: 20

    width: 81 + rightInset
    height: 136
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "xpluna-volume"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    property bool hadFocus: false

    onVisibleChanged: hadFocus = false

    onActiveChanged: {
        if (active)
            hadFocus = true
        else if (hadFocus && visible)
            visible = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: window.visible
        onActivated: window.visible = false
    }

    SystemVolumeContent{
        x: 0
        y: 0
        width: 81
        height: parent.height

        Maia.MaskArea {
            anchors.fill: parent
        }
    }
}
