import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia
import Maia.Notifications.Center
import Maia.Tray
import MaiaFrontend

import "controlcenter"
import "dock"
import "library"
import "notifications"
import "session"
import "status"
import "tray"

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
            if (!dock.dragging) {
                root.publishDock()
                settleTimer.restart()
            }
        }
    }

    // Tells the other layers where the dock goes at the moment of the release, not when it has
    // arrived: what keeps clear of it (the banners) moves together with it
    function publishDock() {
        ShellState.dockEdge = dock.edge
        ShellState.dockStrip = stripThickness
        ShellState.dockScreen = screen ? screen.name : ""
    }

    Component.onCompleted: {
        publishDock()
        // This layer has just started: nothing of it is open, whatever the last one left behind
        ShellState.notificationCenterOpen = false
        ShellState.modalOpen = modalOpen
    }
    onScreenChanged: publishDock()


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
                                             || root.notificationCenterOpen || root.trayOpen
                                             ? LayerShell.Window.KeyboardInteractivityExclusive
                                             : LayerShell.Window.KeyboardInteractivityNone

    // The session screen (sleep, restart, shut down, log out) is open
    property bool sessionOpen: false
    // The Control Center is open
    property bool controlCenterOpen: false
    // The notification center is open; the other layers know through ShellState (no banners meanwhile)
    property bool notificationCenterOpen: false
    // The tray's panel ("+N") or the menu of one of its items is open
    property bool trayPanelOpen: false
    property int trayMenuItemId: 0
    property Item trayMenuAnchor: null
    readonly property bool trayOpen: trayPanelOpen || trayMenuItemId !== 0
    // Something here has the screen; the pill of a job stays out of its way
    readonly property bool modalOpen: dock.libraryOpen || sessionOpen || controlCenterOpen || notificationCenterOpen || trayOpen
    onModalOpenChanged: ShellState.modalOpen = modalOpen

    // One overlay at a time: the App Library, the Control Center, the notification center, the
    // session screen. The one that opens closes the others; the window that had the keyboard before
    // the first one gets it back when the last closes.
    onControlCenterOpenChanged: {
        if (!controlCenterOpen)
            return
        if (!dock.libraryOpen && !sessionOpen && !notificationCenterOpen && !trayOpen)
            dock.rememberFocus()
        dock.libraryOpen = false
        sessionOpen = false
        notificationCenterOpen = false
        closeTray()
    }
    onNotificationCenterOpenChanged: {
        ShellState.notificationCenterOpen = notificationCenterOpen
        // Seen when it opens, and what came while it was open when it closes
        ShellState.notificationsSeenAt = Date.now()
        if (!notificationCenterOpen)
            return
        if (!dock.libraryOpen && !sessionOpen && !controlCenterOpen && !trayOpen)
            dock.rememberFocus()
        dock.libraryOpen = false
        sessionOpen = false
        controlCenterOpen = false
        closeTray()
    }
    onSessionOpenChanged: {
        if (sessionOpen) {
            controlCenterOpen = false
            notificationCenterOpen = false
            closeTray()
        }
    }
    onTrayOpenChanged: {
        if (!trayOpen)
            return
        if (!dock.libraryOpen && !sessionOpen && !controlCenterOpen && !notificationCenterOpen)
            dock.rememberFocus()
        dock.libraryOpen = false
        sessionOpen = false
        controlCenterOpen = false
        notificationCenterOpen = false
    }

    function closeTray() {
        trayMenuItemId = 0
        trayPanelOpen = false
    }

    // The menu of a tray item; the same item again closes it
    function openTrayMenu(itemId, icon) {
        if (trayMenuItemId === itemId) {
            trayMenuItemId = 0
            return
        }
        trayMenuItemId = 0
        trayMenuAnchor = icon
        trayMenuItemId = itemId
    }

    // A primary click on a tray item: what is open closes, the application decides the rest
    function activateTrayItem(itemId) {
        closeTray()
        Tray.activate(itemId, 0, 0, root)
    }
    Connections {
        target: dock

        function onLibraryOpenChanged() {
            if (dock.libraryOpen) {
                root.controlCenterOpen = false
                root.notificationCenterOpen = false
                root.closeTray()
            }
        }
    }

    // The list of the notification center and what is unread, for the panel and the badge
    NotificationGroupsModel {
        id: notificationGroups

        seenUntil: ShellState.notificationsSeenAt
    }

    // The jobs: the "Activities" of the panel and the ring by the clock
    JobsModel {
        id: shellJobs
    }

    // "2 more" on the pill of a job, in the overlay layer
    Connections {
        target: ShellState

        function onNotificationCenterRequested() {
            root.notificationCenterOpen = true
        }
    }

    // The tray: what fits on its plate (those that need attention first), and every item for its panel
    TrayItemsModel {
        id: trayShown

        filter: TrayItemsModel.Shown
        maximumCount: trayButton.capacity
    }

    TrayItemsModel {
        id: trayAll
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
        notificationsChecked: root.notificationCenterOpen
        unreadCount: notificationGroups.unseen
        jobsRunning: shellJobs.runningCount
        jobsPercent: shellJobs.percent
        layout: controlCenterState.buttonLayout
        // Right end of a horizontal strip, top end of a vertical one
        x: placedEdge === Qt.LeftEdge ? dock.edgeMargin + (dock.shortSize - width) / 2
         : placedEdge === Qt.RightEdge ? root.width - dock.edgeMargin - (dock.shortSize + width) / 2
         : root.width - endMargin - width
        y: placedEdge === Qt.TopEdge ? dock.edgeMargin + (dock.shortSize - height) / 2
         : placedEdge === Qt.BottomEdge ? root.height - dock.edgeMargin - (dock.shortSize + height) / 2
         : endMargin

        onClicked: root.controlCenterOpen = !root.controlCenterOpen
        onTimeClicked: root.notificationCenterOpen = !root.notificationCenterOpen
    }

    // The system tray, a plate of its own next to the clock's: below it along a vertical strip, to
    // its left along a horizontal one, with the clock's width or height. Moves with the dock like it.
    TrayButton {
        id: trayButton

        items: trayShown
        totalCount: Tray.count
        edge: root.anchoredEdge
        crossSize: vertical ? controlCenterButton.width : controlCenterButton.height
        checked: root.trayPanelOpen
        menuItemId: root.trayMenuItemId
        x: vertical ? controlCenterButton.x + (controlCenterButton.width - width) / 2 : controlCenterButton.x - 10 - width
        y: vertical ? controlCenterButton.y + controlCenterButton.height + 10 : controlCenterButton.y + (controlCenterButton.height - height) / 2

        onActivated: itemId => root.activateTrayItem(itemId)
        onSecondaryActivated: itemId => Tray.secondaryActivate(itemId, 0, 0, root)
        onMenuRequested: (itemId, icon) => root.openTrayMenu(itemId, icon)
        onContextMenuRequested: itemId => Tray.contextMenu(itemId, 0, 0)
        onScrolled: (itemId, delta, horizontal) => Tray.scroll(itemId, delta, horizontal)
        onMoreClicked: {
            root.trayMenuItemId = 0
            root.trayPanelOpen = !root.trayPanelOpen
        }
    }

    Maia.MaskArea {
        x: trayButton.x
        y: trayButton.y
        width: trayButton.width
        height: trayButton.height
        visible: trayButton.wanted
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
            if (!dock.libraryOpen && !root.sessionOpen && !root.notificationCenterOpen)
                dock.returnFocus()
        }
    }

    // Above the dock, like the Control Center, in the corner of the same button
    NotificationCenterSheet {
        id: notificationCenter

        anchors.fill: parent
        open: root.notificationCenterOpen
        groups: notificationGroups
        jobs: shellJobs
        dockEdge: controlCenterButton.placedEdge
        dockStrip: root.stripThickness

        onCloseRequested: root.notificationCenterOpen = false
        onOpenUrlRequested: url => controlCenterState.launch("xdg-open " + url.replace(/ /g, "%20"))
        onDismissed: {
            if (!dock.libraryOpen && !root.sessionOpen && !root.controlCenterOpen)
                dock.returnFocus()
        }
    }

    // Above the dock: the tray's panel and the menus of its items, beside the strip next to the plate
    TrayOverlay {
        id: trayOverlay

        anchors.fill: parent
        allItems: trayAll
        panelOpen: root.trayPanelOpen
        menuItemId: root.trayMenuItemId
        menuAnchor: root.trayMenuAnchor
        plate: trayButton
        dockEdge: trayButton.placedEdge
        dockStrip: root.stripThickness

        onCloseRequested: root.closeTray()
        onMenuCloseRequested: root.trayMenuItemId = 0
        onActivated: itemId => root.activateTrayItem(itemId)
        onSecondaryActivated: itemId => Tray.secondaryActivate(itemId, 0, 0, root)
        onMenuRequested: (itemId, icon) => root.openTrayMenu(itemId, icon)
        onContextMenuRequested: itemId => {
            root.closeTray()
            Tray.contextMenu(itemId, 0, 0)
        }
        onScrolled: (itemId, delta, horizontal) => Tray.scroll(itemId, delta, horizontal)
        onDismissed: {
            if (!dock.libraryOpen && !root.sessionOpen && !root.controlCenterOpen && !root.notificationCenterOpen)
                dock.returnFocus()
        }
    }

    Maia.MaskArea {
        anchors.fill: parent
        visible: trayOverlay.open
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
