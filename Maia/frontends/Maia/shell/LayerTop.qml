import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import "controlcenter"
import "dock"
import "library"
import "session"
import "status"

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
    // both perpendicular edges, and reserves a strip along that edge (exclusion zone): screen edge,
    // margin, dock, the same margin again, and only then maximized windows, so the dock sits
    // between two equal gaps. The exclusion zone is the distance
    // from the anchored edge, independent of the window size, so the window keeps its size.
    //
    // Anchors and exclusion zone change only once the dock rests at its new edge (released and
    // snapped); while it is dragged they stay at the old edge. That edge is kept between sessions
    // (DockState), so the dock and the window start where they were left.

    DockState {
        id: dockState
    }

    // The edge the window is anchored to and reserves
    readonly property int anchoredEdge: dockState.edge
    readonly property int stripThickness: dock.edgeMargin + dock.shortSize + dock.edgeMargin

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

    // Moves anchors and exclusion zone to the edge the dock rests at, and keeps it
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
            dockState.setEdge(dock.edge)
        }
    }

    Connections {
        target: dock

        function onDraggingChanged() {
            if (!dock.dragging)
                settleTimer.restart()
        }
    }


    // Na Waylandzie pozycji okna nie ustawia się przez x/y (kompozytor je ignoruje),
    // tylko przez layer-shell: warstwę i kotwiczenie do krawędzi ekranu.
    // Kotwiczenie odpowiada anchorom MProxyWindow w Main.qml (prawy górny róg).
    LayerShell.Window.scope: "maia-top-layer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: layerAnchors
    LayerShell.Window.exclusionZone: stripThickness
    // The keyboard only while the App Library is open: its search field takes the typing at once.
    // Otherwise the window never takes the keyboard from the applications.
    LayerShell.Window.keyboardInteractivity: dock.libraryOpen || root.sessionOpen || root.controlCenterOpen
                                             ? LayerShell.Window.KeyboardInteractivityExclusive
                                             : LayerShell.Window.KeyboardInteractivityNone

    // The session screen (sleep, restart, shut down, log out) is open
    property bool sessionOpen: false
    // The Control Center is open
    property bool controlCenterOpen: false

    // One overlay at a time: the App Library, the Control Center, the session screen. The one that
    // opens closes the others; the window that had the keyboard before the first one gets it back
    // when the last closes.
    onControlCenterOpenChanged: {
        if (!controlCenterOpen)
            return
        if (!dock.libraryOpen && !sessionOpen)
            dock.rememberFocus()
        dock.libraryOpen = false
        sessionOpen = false
    }
    onSessionOpenChanged: {
        if (sessionOpen)
            controlCenterOpen = false
    }
    Connections {
        target: dock

        function onLibraryOpenChanged() {
            if (dock.libraryOpen)
                root.controlCenterOpen = false
        }
    }

    // Wi-Fi, the volume and the rest of the Control Center, shared by its button and the modules
    ControlCenterState {
        id: controlCenterState
    }

    // NetworkManager asks for a password (joining a network from the Wi-Fi settings, a saved
    // password refused): the network list of the Control Center asks it
    Connections {
        target: controlCenterState.wifiPrompt

        function onPendingChanged() {
            if (!controlCenterState.wifiPrompt.pending)
                return
            controlCenter.page = "wifi"
            root.controlCenterOpen = true
        }
    }

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

    // The power button, at one end of the strip the dock reserves (see StatusArea.qml); the light /
    // dark mode is in the Control Center. Follows the anchored edge, i.e. moves once the dock rests
    // at a new edge. Below the App Library, which dims it.
    StatusArea {
        id: statusArea

        readonly property real endMargin: 2 * dock.edgeMargin

        edge: root.anchoredEdge
        sessionOpen: root.sessionOpen
        // Left end of a horizontal strip, bottom end of a vertical one
        x: placedEdge === Qt.LeftEdge ? dock.edgeMargin + (dock.shortSize - width) / 2
         : placedEdge === Qt.RightEdge ? root.width - dock.edgeMargin - (dock.shortSize + width) / 2
         : endMargin
        y: placedEdge === Qt.TopEdge ? dock.edgeMargin + (dock.shortSize - height) / 2
         : placedEdge === Qt.BottomEdge ? root.height - dock.edgeMargin - (dock.shortSize + height) / 2
         : root.height - endMargin - height

        onPowerClicked: {
            dock.libraryOpen = false
            dock.rememberFocus()
            root.sessionOpen = true
        }
    }

    // The time and the state of Wi-Fi, volume and battery at the other end of the strip the dock
    // reserves than the power button: opens the Control Center. Moves with the dock
    // like the power button. Below the App Library, which dims it.
    ControlCenterButton {
        id: controlCenterButton

        readonly property real endMargin: 2 * dock.edgeMargin

        controlCenter: controlCenterState
        edge: root.anchoredEdge
        checked: root.controlCenterOpen
        // Right end of a horizontal strip, top end of a vertical one
        x: placedEdge === Qt.LeftEdge ? dock.edgeMargin + (dock.shortSize - width) / 2
         : placedEdge === Qt.RightEdge ? root.width - dock.edgeMargin - (dock.shortSize + width) / 2
         : root.width - endMargin - width
        y: placedEdge === Qt.TopEdge ? dock.edgeMargin + (dock.shortSize - height) / 2
         : placedEdge === Qt.BottomEdge ? root.height - dock.edgeMargin - (dock.shortSize + height) / 2
         : endMargin

        onClicked: root.controlCenterOpen = !root.controlCenterOpen
    }

    AppLibrary {
        id: library

        anchors.fill: parent
        open: dock.libraryOpen
        originItem: dock.libraryButton
        dockEdge: dock.edge
        dockStrip: root.stripThickness

        onCloseRequested: dock.libraryOpen = false
        onDismissed: dock.returnFocus()
    }

    // While the dock is dragged, the whole window receives input
    // Maia.MaskArea {
    //     anchors.fill: parent
    //     visible: dock.dragging
    // }

    Dock {
        id: dock

        // Where it was left; dragging sets the edge itself afterwards
        edge: dockState.edge
    }

    // Above the dock: while it is open the screen belongs to it (modal, like the session screen).
    // Its modules gather in the corner of its button.
    ControlCenter {
        id: controlCenter

        anchors.fill: parent
        open: root.controlCenterOpen
        controlCenter: controlCenterState
        dockEdge: controlCenterButton.placedEdge
        dockStrip: root.stripThickness

        onCloseRequested: root.controlCenterOpen = false
        onDismissed: {
            if (!dock.libraryOpen && !root.sessionOpen)
                dock.returnFocus()
        }
    }

    // Above everything, the dock included: the session concerns the whole computer
    SessionScreen {
        id: sessionScreen

        anchors.fill: parent
        open: root.sessionOpen

        onCloseRequested: root.sessionOpen = false
        onDismissed: dock.returnFocus()
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
