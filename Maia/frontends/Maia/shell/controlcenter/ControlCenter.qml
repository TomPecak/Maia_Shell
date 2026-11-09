pragma ComponentBehavior: Bound

import QtQuick

import Maia.Backend as Maia
import MaiaFrontend

// The Control Center in the style of iPadOS 18, opened by its button at one end of the dock strip
// (ControlCenterButton.qml).
//
// Its modules gather in the corner of the screen where the button is (as in the top right corner
// of iPadOS), so the pointer's way from the button to them is short (Fitts's law). They lie on the
// dimmed (and, where the compositor blurs, blurred) desktop one by one, grouped by meaning (common
// region): the connections; the appearance; the sliders of brightness and volume; small toggles;
// the battery and the settings. Opening, they grow out of the corner one after the other, the
// nearest first, with a soft spring; closing, they go back the same way, faster.
//
// "Wi-Fi" in the connections module turns the modules into the network list (WifiModule.qml), in
// the same corner; Back or Escape returns. Closes by a click outside of the modules, Escape, or
// the button. While it is open the whole screen belongs to it, the dock included (modal, like the
// session screen).
//
// Fills the whole window; the input region of the window covers it only while it is shown.
Item {
    id: center

    // --- Public API ---

    property bool open: false
    property ControlCenterState controlCenter
    // Edge of the dock and the strip it reserves there: the button is at the right end of a
    // horizontal strip and the top end of a vertical one, and the modules gather next to it
    property int dockEdge: Qt.BottomEdge
    property real dockStrip: 0
    // "main" (the modules) or "wifi" (the network list)
    property string page: "main"

    // Asks to be closed (Escape, a click outside, an action that leaves the Control Center)
    signal closeRequested()
    // Closed: the window that had the keyboard before should get it back
    signal dismissed()

    // Shown from opening until the closing animation has finished (Animators, see MenuPanel.qml)
    property bool shown: false

    visible: shown

    onOpenChanged: open ? d.show() : d.hide()

    // --- Layout ---

    // One cell of the grid of modules, and the gap between cells
    readonly property real unit: 80
    readonly property real gap: 14
    readonly property real gridSize: 4 * unit + 3 * gap
    readonly property real dockGap: 12
    readonly property real screenMargin: 16

    // The corner the modules gather in, next to the button
    readonly property bool atRight: dockEdge !== Qt.LeftEdge
    readonly property bool atBottom: dockEdge === Qt.BottomEdge

    // --- Dimming ---

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: Theme.controlCenterScrim
        opacity: 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: center.closeRequested()
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    // Takes the keyboard while it is open
    Item {
        id: keyHandler

        focus: true
    }

    // Escape from anywhere inside (a password field too): back from the network list, then close
    Keys.onEscapePressed: {
        if (center.page !== "main")
            center.page = "main"
        else
            center.closeRequested()
    }

    // --- The modules ---

    Item {
        id: frame

        width: center.gridSize
        // The larger of the two pages: neither jumps while they change places
        height: Math.max(center.gridSize, wifiPage.height)

        x: center.dockEdge === Qt.LeftEdge ? center.dockStrip + center.dockGap
         : center.dockEdge === Qt.RightEdge ? center.width - center.dockStrip - center.dockGap - width
         : center.width - center.screenMargin - width
        y: center.dockEdge === Qt.TopEdge ? center.dockStrip + center.dockGap
         : center.atBottom ? center.height - center.dockStrip - center.dockGap - height
         : center.screenMargin

        // The grid of modules; fades and shrinks a little towards the corner while the network list
        // takes its place
        Item {
            id: grid

            width: center.gridSize
            height: center.gridSize
            // With the dock at the bottom the modules gather above it, from the bottom up
            y: center.atBottom ? frame.height - height : 0
            visible: d.pageProgress < 1
            opacity: 1 - d.pageProgress
            scale: 1 - 0.06 * d.pageProgress
            transformOrigin: d.cornerOrigin

            ConnectivityModule {
                controlCenter: center.controlCenter
                x: d.cellX(0); y: d.cellY(0)
                width: d.span(2); height: d.span(2)
                appear: d.appear(0, 0, 2, 2)
                transformOrigin: d.cornerOrigin
                onWifiDetailsRequested: center.page = "wifi"
            }

            WideTile {
                x: d.cellX(2); y: d.cellY(0)
                width: d.span(2); height: d.span(1)
                appear: d.appear(2, 0, 2, 1)
                transformOrigin: d.cornerOrigin
                title: qsTr("Dark Mode")
                subtitle: Theme.dark ? qsTr("On") : qsTr("Off")
                checked: Theme.dark
                onColor: Theme.indigo
                glyph: Component {
                    ModeGlyph {
                        moon: Theme.dark
                        ink: Theme.dark ? "white" : Theme.label
                    }
                }
                onClicked: Theme.setDark(!Theme.dark)
            }

            VerticalSlider {
                x: d.cellX(2); y: d.cellY(1)
                width: d.span(1); height: d.span(2)
                appear: d.appear(2, 1, 1, 2)
                transformOrigin: d.cornerOrigin
                title: qsTr("Brightness")
                icon: center.controlCenter.icon("brightness-high-symbolic")
                value: center.controlCenter.brightness
                onMoved: function (value) { center.controlCenter.brightness = value }
            }

            VerticalSlider {
                x: d.cellX(3); y: d.cellY(1)
                width: d.span(1); height: d.span(2)
                appear: d.appear(3, 1, 1, 2)
                transformOrigin: d.cornerOrigin
                title: qsTr("Volume")
                icon: center.controlCenter.volumeIcon
                value: center.controlCenter.muted ? 0 : center.controlCenter.volume
                onMoved: function (value) { center.controlCenter.setVolume(value) }
                onGlyphClicked: center.controlCenter.toggleMuted()
            }

            SmallTile {
                x: d.cellX(0); y: d.cellY(2)
                width: d.span(1); height: d.span(1)
                appear: d.appear(0, 2, 1, 1)
                transformOrigin: d.cornerOrigin
                title: qsTr("Night Light")
                icon: center.controlCenter.icon("redshift-status-on-symbolic")
                onColor: Theme.orange
                checked: center.controlCenter.nightLight
                onClicked: center.controlCenter.nightLight = !center.controlCenter.nightLight
            }

            // TEMPORARY: trying out the layouts of the Control Center button
            LayoutTile {
                x: d.cellX(1); y: d.cellY(2)
                width: d.span(1); height: d.span(1)
                appear: d.appear(1, 2, 1, 1)
                transformOrigin: d.cornerOrigin
                current: center.controlCenter.buttonLayoutIndex
                count: center.controlCenter.buttonLayoutNames.length
                currentName: center.controlCenter.buttonLayoutNames[current] ?? ""
                onLayoutRequested: function (layout) { center.controlCenter.setButtonLayout(layout) }
            }

            WideTile {
                x: d.cellX(0); y: d.cellY(3)
                width: d.span(2); height: d.span(1)
                appear: d.appear(0, 3, 2, 1)
                transformOrigin: d.cornerOrigin
                interactive: false
                title: qsTr("Battery")
                subtitle: center.controlCenter.batteryCharging
                          ? qsTr("%1 %, charging").arg(center.controlCenter.batteryLevel)
                          : qsTr("%1 %").arg(center.controlCenter.batteryLevel)
                icon: center.controlCenter.batteryIcon
                checked: true
                onColor: center.controlCenter.batteryLevel <= 20 ? Theme.red : Theme.green
            }

            // The hotspot shares this computer's internet; setting it up (name, password) belongs
            // to the Wi-Fi settings, so the tile shows its state and opens them
            SmallTile {
                x: d.cellX(2); y: d.cellY(3)
                width: d.span(1); height: d.span(1)
                appear: d.appear(2, 3, 1, 1)
                transformOrigin: d.cornerOrigin
                title: qsTr("Personal Hotspot")
                icon: center.controlCenter.icon("network-wireless-hotspot-symbolic")
                onColor: Theme.green
                checked: center.controlCenter.wifi.hotspot
                onClicked: d.openSettings("maia-settings --page network")
            }

            SmallTile {
                x: d.cellX(3); y: d.cellY(3)
                width: d.span(1); height: d.span(1)
                appear: d.appear(3, 3, 1, 1)
                transformOrigin: d.cornerOrigin
                title: qsTr("Settings")
                icon: center.controlCenter.icon("configure-symbolic")
                checkable: false
                onClicked: d.openSettings("maia-settings")
            }
        }

        // The network list, in the corner of the modules
        WifiModule {
            id: wifiPage

            controlCenter: center.controlCenter
            width: center.gridSize
            height: implicitHeight
            y: center.atBottom ? frame.height - height : 0
            shown: center.shown && center.page === "wifi"
            visible: d.pageProgress > 0
            appear: d.pageProgress
            transformOrigin: d.cornerOrigin

            onBackRequested: center.page = "main"
            onSettingsRequested: d.openSettings("maia-settings --page network")
        }
    }

    // --- Animations ---
    //
    // Opening and closing are one number, d.progress (0: closed, 1: open). Each module appears over
    // a part of it, the nearer to the corner the earlier, with a spring of its own (d.appear), so
    // the cascade always moves together; a NumberAnimation on the GUI thread, like the App Library.

    NumberAnimation {
        id: openAnimation

        target: d
        property: "progress"
        to: 1
        duration: 560
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: closeAnimation

        target: d
        property: "progress"
        to: 0
        duration: 300
        easing.type: Easing.Linear
        onFinished: {
            center.shown = center.open
            if (!center.open)
                center.page = "main"
        }
    }

    // Between the modules and the network list
    NumberAnimation {
        id: pageAnimation

        target: d
        property: "pageProgress"
        duration: 260
        easing.type: Easing.OutCubic
    }

    onPageChanged: {
        pageAnimation.to = page === "wifi" ? 1 : 0
        pageAnimation.restart()
        if (page === "main")
            keyHandler.forceActiveFocus()
    }

    // --- Private ---

    QtObject {
        id: d

        // 0 closed, 1 open
        property real progress: 0
        // 0 the modules, 1 the network list
        property real pageProgress: 0

        // The scrim follows the opening, without a spring
        readonly property real scrimOpacity: Math.min(1, progress * 1.6)

        // Each module grows over this part of the opening; the delays fill the rest
        readonly property real span1: 0.62

        readonly property int cornerOrigin: center.atRight ? (center.atBottom ? Item.BottomRight : Item.TopRight)
                                                           : (center.atBottom ? Item.BottomLeft : Item.TopLeft)

        function span(cells) {
            return cells * center.unit + (cells - 1) * center.gap
        }
        function cellX(column) {
            return column * (center.unit + center.gap)
        }
        function cellY(row) {
            return row * (center.unit + center.gap)
        }

        // How far a module (its cells) has appeared: the cell nearest to the corner of the button
        // decides when it starts
        function appear(column, row, columns, rows) {
            const fromSide = center.atRight ? 4 - (column + columns) : column
            const fromEdge = center.atBottom ? 4 - (row + rows) : row
            const delay = (fromSide + fromEdge) / 6 * (1 - span1)
            const t = Math.max(0, Math.min(1, (progress - delay) / span1))
            return springOut(t)
        }

        // An ease out with a small overshoot, like the springs of iPadOS
        function springOut(t) {
            const s = 1.2
            const u = t - 1
            return 1 + (s + 1) * u * u * u + s * u * u
        }

        function openSettings(command) {
            center.controlCenter.launch(command)
            center.closeRequested()
        }

        function show() {
            closeAnimation.stop()
            if (!center.shown) {
                progress = 0
                pageProgress = center.page === "wifi" ? 1 : 0
            }
            center.shown = true
            openAnimation.restart()
            if (center.Window.window)
                center.Window.window.requestActivate()
            keyHandler.forceActiveFocus()
        }

        function hide() {
            openAnimation.stop()
            closeAnimation.restart()
            center.dismissed()
        }
    }

    Binding {
        target: scrim
        property: "opacity"
        value: d.scrimOpacity
    }
}
