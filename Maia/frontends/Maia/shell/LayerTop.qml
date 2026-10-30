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
    // While the dock is dragged or its panel is open, the window covers the whole screen (anchored
    // to all edges): the dock follows the pointer anywhere, the panel has room and a click anywhere
    // closes it. Once the dock rests at an edge, the window becomes a strip along that edge
    // (anchored to it and to both perpendicular edges), as thick as the dock with its margin, and
    // reserves the strip (exclusion zone): maximized windows end before it.
    //
    // Anchors and size reach the compositor in separate requests, so they change in an order
    // where every state in between still covers the whole screen: docking sets the anchors first
    // and the size after them, undocking the size first and the anchors after it.

    readonly property int allEdges: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
                                    | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    // The edge of the dock and both perpendicular edges
    readonly property int stripEdges: {
        switch (dock.edge) {
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
    readonly property int stripThickness: dock.edgeMargin + dock.shortSize

    // The two halves of the docked state, see the order above
    property bool stripAnchors: false
    property bool stripSize: false

    readonly property int layerAnchors: stripAnchors ? stripEdges : allEdges

    width: stripSize && dock.vertical ? stripThickness : Screen.width
    height: stripSize && !dock.vertical ? stripThickness : Screen.height

    function setDocked(docked) {
        if (stripAnchors === docked && stripSize === docked)
            return
        console.log("[LayerTop]", docked ? "docking to the" : "undocking from the",
                    ["top", "left", "right", "bottom"][[Qt.TopEdge, Qt.LeftEdge, Qt.RightEdge, Qt.BottomEdge].indexOf(dock.edge)],
                    "edge, strip", stripThickness, "px")
        // The coordinates of the dock in the window jump with the window, without animation
        dock.instant = true
        instantTimer.restart()
        if (docked) {
            stripAnchors = true
            Qt.callLater(() => { root.stripSize = true })
        } else {
            stripSize = false
            Qt.callLater(() => { root.stripAnchors = false })
        }
    }

    // Docks once the dock rests: released, the snapping animation over, the panel closed
    Timer {
        id: settleTimer

        interval: 500
        onTriggered: {
            if (!dock.dragging && !dock.panelOpen)
                root.setDocked(true)
        }
    }

    Timer {
        id: instantTimer

        interval: 300
        onTriggered: dock.instant = false
    }

    Connections {
        target: dock

        function onDraggingChanged() {
            if (dock.dragging)
                root.setDocked(false)
            else
                settleTimer.restart()
        }
        function onPanelOpenChanged() {
            if (dock.panelOpen)
                root.setDocked(false)
            else
                settleTimer.restart()
        }
    }

    // Position of the window on the screen, from its size and the edge of the dock (a strip at the
    // bottom or right edge starts away from the screen origin)
    function screenOrigin() {
        if (width < Screen.width && dock.edge === Qt.RightEdge)
            return Qt.point(Screen.width - width, 0)
        if (height < Screen.height && dock.edge === Qt.BottomEdge)
            return Qt.point(0, Screen.height - height)
        return Qt.point(0, 0)
    }

    property point lastOrigin: Qt.point(0, 0)

    // The size took effect: a dragged dock keeps its place on the screen
    function originMayHaveMoved() {
        const origin = screenOrigin()
        if (dock.dragging)
            dock.shiftPointer(origin.x - lastOrigin.x, origin.y - lastOrigin.y)
        lastOrigin = origin
    }

    onWidthChanged: originMayHaveMoved()
    onHeightChanged: originMayHaveMoved()

    Component.onCompleted: settleTimer.start()


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-top-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: layerAnchors
    LayerShell.Window.exclusionZone: stripAnchors ? stripThickness : 0
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
