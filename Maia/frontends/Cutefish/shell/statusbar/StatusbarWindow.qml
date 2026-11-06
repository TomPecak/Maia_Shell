import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

// The status bar: a layer-shell strip along the top edge (top layer) that reserves its height,
// so maximized windows start below it. It never takes the keyboard focus.
Window {
    id: statusbarWindow

    property alias wallpaperUrl: statusbarContent.wallpaperUrl

    flags: Qt.FramelessWindowHint
    color: "transparent"

    width: Screen.width
    height: 25

    LayerShell.Window.scope: "cutefish-statusbar"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: height
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    MWindowBlur {
        window: statusbarWindow
        enabled: true
    }

    StatusbarContent{
        id: statusbarContent
        anchors.fill: parent

        windowX: statusbarWindow.x
        windowY: statusbarWindow.y
        windowWidth: statusbarWindow.width
        windowHeight: statusbarWindow.height
    }
}
