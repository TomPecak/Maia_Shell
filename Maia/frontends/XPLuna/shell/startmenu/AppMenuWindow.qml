import QtQuick
import org.kde.layershell 1.0 as LayerShell

// The start menu: a layer-shell surface in the bottom left corner. The taskbar's exclusion zone
// puts it right above the taskbar, as in Windows XP. It takes the keyboard while open and closes
// when it loses it (a click into a window), on Escape, or when the menu asks (an app started).
//
// Open and close it with `visible`.
Window {
    id: root

    signal logoutClicked()
    signal turnoffClicked()

    width: 380
    height: 478
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: false

    LayerShell.Window.scope: "xpluna-startmenu"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    // The focus is lost only after it was had (a surface is not active the moment it is shown)
    property bool hadFocus: false

    onVisibleChanged: {
        hadFocus = false
        if (!visible)
            appMenuContent.resetState()
    }

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

    AppMenuContent{
        id: appMenuContent
        onHideRequest:{
            root.visible = false
        }
        onLogoutClicked: {
            root.logoutClicked()
        }
        onTurnoffClicked: {
            root.turnoffClicked()
        }
    }
}
