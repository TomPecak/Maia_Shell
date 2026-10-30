import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

import "menu"

Window{
    id: root

    visible: true


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-bottom-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerBottom
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    // -1: the wallpaper stays full screen below the dock. 0 would mean "move away from the exclusion
    // zones of other surfaces", and the compositor would shrink it when the dock reserves its strip.
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    color: "orange"

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl("../assets/waves-macos-big-sur.jpg")


    }

    // A right click on the wallpaper opens the context menu of the desktop
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => desktopMenu.popup(eventPoint.position.x, eventPoint.position.y)
    }

    DesktopMenu {
        id: desktopMenu
    }


    AvailableFonts{
    //anchors.centerIn: parent
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    }


}
