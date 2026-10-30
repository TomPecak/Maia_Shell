import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import "dock"

Window{
    id: root

    visible: true

    // Preview of the window: its whole area tinted and a red strip on every anchored edge,
    // like in the Experimental frontend
    // Temporarily off; true shows the preview again
    property bool showWindowArea: false

    // --- Docking (experiment) ---
    //
    // The window always covers the whole screen: the dock can be dragged anywhere, its panel has
    // room and a click anywhere closes it. It is anchored to the edge the dock rests at and to
    // both perpendicular edges, and reserves a strip along that edge (exclusion zone), as thick as
    // the dock with its margin: maximized windows end before it. The exclusion zone is the distance
    // from the anchored edge, independent of the window size, so the window keeps its size.
    //
    // Anchors and exclusion zone change only once the dock rests at its new edge (released and
    // snapped); while it is dragged they stay at the old edge.

    // The edge the window is anchored to and reserves
    property int anchoredEdge: Qt.TopEdge
    readonly property int stripThickness: dock.edgeMargin + dock.shortSize

    // anchoredEdge and both perpendicular edges
    readonly property int layerAnchors: {
        switch (anchoredEdge) {
        case Qt.TopEdge:
            return LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        case Qt.BottomEdge:
            return LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
        case Qt.LeftEdge:
            return LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
        default:
            return LayerShell.Window.AnchorRight | LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
        }
    }

    // Anchored to three edges only, so the size along the fourth has to be given
    width: Screen.width
    height: Screen.height

    // Moves anchors and exclusion zone to the edge the dock rests at
    Timer {
        id: settleTimer

        // The dock snaps to its edge in 450 ms after the release
        interval: 500
        onTriggered: {
            if (dock.dragging || root.anchoredEdge === dock.edge)
                return
            console.log("[LayerTop] anchored to the",
                        ["top", "left", "right", "bottom"][[Qt.TopEdge, Qt.LeftEdge, Qt.RightEdge, Qt.BottomEdge].indexOf(dock.edge)],
                        "edge, exclusion zone", root.stripThickness, "px")
            root.anchoredEdge = dock.edge
        }
    }

    Connections {
        target: dock

        function onDraggingChanged() {
            if (!dock.dragging)
                settleTimer.restart()
        }
    }

    Component.onCompleted: anchoredEdge = dock.edge


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-top-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: layerAnchors
    LayerShell.Window.exclusionZone: stripThickness
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
