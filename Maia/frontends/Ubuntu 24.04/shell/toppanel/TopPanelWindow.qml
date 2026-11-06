import QtQuick
import org.kde.layershell 1.0 as LayerShell

// The top bar: a layer-shell strip along the top edge that reserves its height (exclusion zone):
// maximized windows start below it, the dock and the control board are placed under it. It never
// takes the keyboard focus.
Window {
    id: window

    // The control board is open (the status area stays highlighted)
    property alias controlBoardVisible: content.controlBoardVisible

    signal clicked()

    width: Screen.width
    height: 29
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: true

    LayerShell.Window.scope: "ubuntu-top-panel"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: height
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    TopPanelContent {
        id: content

        anchors.fill: parent
        onClicked: window.clicked()
    }
}
