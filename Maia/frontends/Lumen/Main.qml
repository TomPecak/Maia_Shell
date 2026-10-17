import QtQuick
import org.kde.layershell 1.0 as LayerShell

import "desktop"
import "services"
import "windows"

// Lumen: modern frontend of Maia Shell in the style of current desktop systems
// (centered taskbar, start menu, quick settings, notification center, widgets).
//
// Every part of the shell is a separate Wayland layer-shell surface, all of them run
// in this process and share Theme (design tokens) and Shell (state) singletons:
// - desktop (this window): wallpaper and desktop clock, background layer,
// - taskbar: bottom edge, reserves its area,
// - flyouts: start menu, calendar and notifications, quick settings, widgets,
// - context menu of the desktop.
Window {
    id: desktop

    width: Screen.width
    height: Screen.height
    color: "black"
    flags: Qt.FramelessWindowHint
    visible: true
    title: "Lumen"

    LayerShell.Window.scope: "lumen-desktop"
    LayerShell.Window.layer: LayerShell.Window.LayerBackground
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // Covers the whole screen, also under the taskbar
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    Wallpaper {
        anchors.fill: parent
    }

    DesktopClock {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingXL * 2
        anchors.rightMargin: Theme.spacingXL * 2
    }

    // A click on the desktop closes the open flyout
    TapHandler {
        onTapped: Shell.closeFlyouts()
    }

    // A right click opens the context menu of the desktop
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => Shell.openDesktopMenu(eventPoint.position.x, eventPoint.position.y)
    }

    // Colors of the applications follow the theme (when enabled in quick settings)
    AppColorSync {}

    TaskbarWindow {}
    StartMenuWindow {}
    CalendarWindow {}
    QuickSettingsWindow {}
    WidgetsWindow {}
    DesktopMenuWindow {}
}
