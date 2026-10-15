import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

Window{
    id: root

    visible: true


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-bottom-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerBottom
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    color: "orange"

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Qt.resolvedUrl("./assets/waves-macos-big-sur.jpg")


    }


    AvailableFonts{
    //anchors.centerIn: parent
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    }


}
