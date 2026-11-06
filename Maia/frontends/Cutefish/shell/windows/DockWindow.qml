import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

import "../contents"

import CutefishFrontend as FishUI

// The dock: a layer-shell surface centred at the bottom edge (top layer), `gap` above the edge.
// It reserves the dock with a gap on both sides (exclusion zone), so maximized windows end above
// it. The window is taller than the dock by the gap; the blur and the input cover the dock only.
Window {
    id: root

    signal appsItemClicked(var mouse)

    property int gap: 6

    width: dockContent.width
    height: dockContent.height + gap

    color: "transparent"
    flags: Qt.FramelessWindowHint

    LayerShell.Window.scope: "cutefish-dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom
    LayerShell.Window.exclusionZone: dockContent.height + 2 * gap
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    MWindowBlur {
        window: root
        geometry: Qt.rect(0, 0, dockContent.width, dockContent.height)
        windowRadius: dockContent.windowRadius
        enabled: true
    }

    DockContent{
        id: dockContent

        MaskArea {
            anchors.fill: parent
        }
        onAppsItemClicked: {
            root.appsItemClicked(mouse)
        }
    }
}
