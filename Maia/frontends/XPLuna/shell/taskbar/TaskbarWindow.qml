import QtQuick
import org.kde.layershell 1.0 as LayerShell

// The taskbar: a layer-shell strip along the bottom edge that reserves its height (exclusion
// zone), so maximized windows and the start menu are placed above it. It never takes the keyboard
// focus: clicking a task keeps the active window active.
Window {
    id: window

    // The start menu is open (the Start button stays pressed)
    property alias startMenuOpen: content.inputMenuVisible

    signal startPressed()
    signal volumeClicked()

    width: Screen.width
    height: content.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: true

    LayerShell.Window.scope: "xpluna-taskbar"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: height
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    TaskbarContent {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        onStartPressed: window.startPressed()
        onVolumeClicked: window.volumeClicked()
    }
}
