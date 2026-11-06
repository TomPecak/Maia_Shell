import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

// The control board (Ubuntu's quick settings): a layer-shell surface in the top right corner,
// placed under the top bar by its exclusion zone, `inset` away from the bar and the screen edge.
//
// The window is as large as the card can grow (its expanding row open) plus the inset, so the
// card grows inside it without the surface being resized; only the card takes input (MaskArea).
// It takes the keyboard while open and closes when it loses it (a click into a window) or on
// Escape.
//
// Open and close it with `visible`.
Window {
    id: root

    property int inset: 6

    width: content.width + inset
    height: content.expandedHeight + inset
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "ubuntu-control-board"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
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
        enabled: root.visible
        onActivated: root.visible = false
    }

    ControlBoardContent{
        id: content

        x: 0
        y: root.inset

        Maia.MaskArea {
            anchors.fill: parent
        }
    }
}
