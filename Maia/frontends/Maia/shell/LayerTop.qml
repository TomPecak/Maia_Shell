import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import "dock"

Window{
    id: root

    visible: true

    // Preview of the window: its whole area tinted and a red strip on every anchored edge,
    // like in the Experimental frontend
    property bool showWindowArea: true

    readonly property int layerAnchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
                                        | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-top-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: layerAnchors
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    //color: "#AA112233"
    color: "transparent"

    // --- Preview of the window area (showWindowArea) ---

    // Translucent tint of the whole window. Drawn by an item: a translucent window color is not
    // premultiplied by Qt and the compositor would show it almost opaque. It takes no input
    // (the input region comes from the MaskArea items).
    Rectangle {
        anchors.fill: parent
        visible: root.showWindowArea
        color: Qt.rgba(0.15, 0.55, 1.0, 0.22)
    }

    // While the dock panel is open, the whole window receives input and a click
    // outside of the panel closes it. Declared first, so it lies below everything else.
    MouseArea {
        anchors.fill: parent
        visible: dock.panelOpen
        onPressed: dock.panelOpen = false

        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    // While the dock is dragged, the whole window receives input
    // Maia.MaskArea {
    //     anchors.fill: parent
    //     visible: dock.dragging
    // }

    AvailableFonts{
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Maia.MaskArea{
            anchors.fill: parent
        }
    }

    Dock {
        id: dock
    }

    // Red strips on the edges the window is anchored to, above everything
    Rectangle {
        anchors.left: parent.left
        width: 4
        height: parent.height
        color: "red"
        visible: root.showWindowArea && (root.layerAnchors & LayerShell.Window.AnchorLeft) !== 0
    }
    Rectangle {
        anchors.right: parent.right
        width: 4
        height: parent.height
        color: "red"
        visible: root.showWindowArea && (root.layerAnchors & LayerShell.Window.AnchorRight) !== 0
    }
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 4
        color: "red"
        visible: root.showWindowArea && (root.layerAnchors & LayerShell.Window.AnchorTop) !== 0
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 4
        color: "red"
        visible: root.showWindowArea && (root.layerAnchors & LayerShell.Window.AnchorBottom) !== 0
    }
}
