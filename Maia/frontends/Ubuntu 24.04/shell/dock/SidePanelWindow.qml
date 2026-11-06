import QtQuick
import org.kde.layershell 1.0 as LayerShell

// The dock (Ubuntu's side panel): a layer-shell strip along the left edge, from the top bar to the
// bottom, that reserves its width (exclusion zone): maximized windows start right of it. It never
// takes the keyboard focus; its context menu is a popup of its own.
Window {
    id: window

    signal launcherButtonClicked()

    width: 66
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: true

    LayerShell.Window.scope: "ubuntu-dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
    LayerShell.Window.exclusionZone: width
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    SidePanelContent {
        anchors.fill: parent
        onLauncherButtonClicked: window.launcherButtonClicked()
    }
}
