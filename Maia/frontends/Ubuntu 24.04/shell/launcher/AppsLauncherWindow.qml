import QtQuick
import org.kde.layershell 1.0 as LayerShell

// The app grid ("Show Apps"): a layer-shell surface anchored to all edges without an exclusion
// zone of its own, so the compositor fits it between the top bar and the dock, as GNOME's overview.
// It takes the keyboard (the search field) and closes when an app is started, on Escape or when
// it loses the focus.
//
// Open and close it with `visible`.
Window {
    id: root

    width: Screen.width
    height: Screen.height
    color: "#222222"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "ubuntu-app-launcher"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
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

    AppLauncherContent{
        anchors.fill: parent
        onAppLaunched: {
            root.visible = false
        }
    }
}
