import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

Window{
    id: root

    visible: true


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-top-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    color: "#AA112233"


    AvailableFonts{
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Maia.MaskArea{
            anchors.fill: parent
        }
    }

}