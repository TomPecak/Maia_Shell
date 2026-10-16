import QtQuick

import Maia.Backend as Maia

// Draggable dock which snaps to the nearest screen edge when it is released.
//
// The dock has to be placed directly in a full-screen item (normally the window
// content item), its parent defines the area in which the dock can be moved.
// Window-wide input handling (closing the panel by clicking outside of it and
// capturing the pointer while dragging) belongs to the window, see LayerTop.qml.
Rectangle {
    id: dock

    // --- Public API ---

    // Size along the edge the dock is attached to and across it
    property real longSize: 700
    property real shortSize: 100
    // Distance from the screen edge
    property real edgeMargin: 15
    // Edge the dock is attached to: Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge or Qt.RightEdge
    property int edge: Qt.TopEdge
    // Whether the launcher panel is open
    property bool panelOpen: false

    readonly property bool vertical: edge === Qt.LeftEdge || edge === Qt.RightEdge
    readonly property bool dragging: d.dragging

    // Final size for the current edge (width/height are animated towards it)
    readonly property real targetWidth: vertical ? shortSize : longSize
    readonly property real targetHeight: vertical ? longSize : shortSize

    // --- Appearance ---

    radius: 20
    color: "#CCFFFFFF"
    border.color: "red"
    border.width: 2

    // "Pressed" effect while the dock is grabbed
    scale: dragArea.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

    // --- Geometry ---

    width: targetWidth
    height: targetHeight

    // While dragging the dock follows the pointer, holding the point it was grabbed by,
    // otherwise it is attached to its edge
    x: {
        if (!parent)
            return 0
        if (d.dragging)
            return d.pointer.x - targetWidth * d.grabRatioX
        if (edge === Qt.LeftEdge)
            return edgeMargin
        if (edge === Qt.RightEdge)
            return parent.width - targetWidth - edgeMargin
        return (parent.width - targetWidth) / 2
    }

    y: {
        if (!parent)
            return 0
        if (d.dragging)
            return d.pointer.y - targetHeight * d.grabRatioY
        if (edge === Qt.TopEdge)
            return edgeMargin
        if (edge === Qt.BottomEdge)
            return parent.height - targetHeight - edgeMargin
        return (parent.height - targetHeight) / 2
    }

    // While dragging the position follows the pointer quickly, after release the dock
    // slowly snaps to its edge. The size always changes slowly.
    Behavior on x { NumberAnimation { duration: d.moveDuration; easing.type: Easing.OutQuart } }
    Behavior on y { NumberAnimation { duration: d.moveDuration; easing.type: Easing.OutQuart } }
    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
    Behavior on height { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }

    // Grabs the dock, it is declared first so that the dock content lies above it
    MouseArea {
        id: dragArea

        anchors.fill: parent
        preventStealing: true

        onPressed: function (mouse) {
            d.beginDrag(mouse.x / dock.width, mouse.y / dock.height,
                        mapToItem(dock.parent, mouse.x, mouse.y))
        }
        onPositionChanged: function (mouse) {
            d.updatePointer(mapToItem(dock.parent, mouse.x, mouse.y))
        }
        onReleased: d.endDrag()
        onCanceled: d.endDrag()
    }

    // The dock area receives input, the rest of the window lets it through
    Maia.MaskArea {
        anchors.fill: parent
    }

    DockButton {
        id: launcherButton

        width: dock.shortSize
        height: dock.shortSize
        // At the beginning of the dock: left in a horizontal dock, top in a vertical one
        x: dock.vertical ? (dock.width - width) / 2 : 0
        y: dock.vertical ? 0 : (dock.height - height) / 2

        onClicked: dock.panelOpen = !dock.panelOpen

        DockPanel {
            open: dock.panelOpen
            edge: dock.edge
        }
    }

    // --- Private state ---

    QtObject {
        id: d

        property bool dragging: false
        // Position animation duration, changed before 'dragging' so the release
        // animation always starts with the slow duration
        property int moveDuration: 450
        // Point the dock was grabbed by, relative to its size (0..1)
        property real grabRatioX: 0.5
        property real grabRatioY: 0.5
        // Pointer position in parent coordinates
        property point pointer: Qt.point(0, 0)

        function beginDrag(ratioX, ratioY, position) {
            grabRatioX = ratioX
            grabRatioY = ratioY
            moveDuration = 50
            updatePointer(position)
            dragging = true
        }

        function endDrag() {
            if (!dragging)
                return
            moveDuration = 450
            dragging = false
        }

        function updatePointer(position) {
            const area = dock.parent
            const px = Math.max(0, Math.min(area.width, position.x))
            const py = Math.max(0, Math.min(area.height, position.y))
            pointer = Qt.point(px, py)

            // Pointer position relative to the screen center (-1..1); the screen is divided
            // into four zones by its diagonals, each zone belongs to one edge
            const nx = (px / area.width) * 2 - 1
            const ny = (py / area.height) * 2 - 1
            if (Math.abs(nx) > Math.abs(ny))
                dock.edge = nx > 0 ? Qt.RightEdge : Qt.LeftEdge
            else
                dock.edge = ny > 0 ? Qt.BottomEdge : Qt.TopEdge
        }
    }
}
