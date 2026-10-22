import QtQuick
import org.kde.layershell 1.0 as LayerShell

// Experiment: moving a dock-like bar across the whole screen with a single layer-shell window.
//
// The window lies on the top layer, is anchored to the top and bottom edges and to one side
// edge. One half of the cycle (from the left edge to the right one):
//   1. expand the window to the full width (anchored left, the window grows to the right),
//   2. wait,
//   3. anchor the right edge as well (the window is anchored to both side edges), wait,
//   4. move the bar inside the window to the right edge,
//   5. wait,
//   6. release the left edge (anchored right only), wait,
//   7. shrink the window to the dock width (the left edge of the window moves to the right),
//   8. wait.
// The second half is the mirror image, from the right edge back to the left one, and the
// cycle repeats forever. Everything is slow on purpose, so a human can follow every step and
// notice glitches. A click on the bar pauses / resumes the sequence.
//
// The window is translucent, so its area is visible; a thin red strip marks every side edge
// the window is anchored to at the moment (top and bottom are always anchored).
//
// This file runs in a separate client process, started by MProxyWindow in Main.qml.
// The process gets the initial geometry from the MProxyWindow item, all changes of the
// geometry and anchors are made here. The process has this one window only: with more
// windows in one process the QML animations are not synchronized with the frames and jump.
// The panel with the state of the experiment is a part of the window.
Window {
    id: window

    // Width of the window while it holds only the bar
    readonly property int dockWidth: 96
    readonly property int barWidth: 64
    readonly property int barMargin: (dockWidth - barWidth) / 2
    readonly property int fullWidth: Screen.width

    // --- Timing ---

    readonly property int resizeDuration: 5000
    readonly property int moveDuration: 5000
    readonly property int pauseDuration: 2000

    // --- State, shown by the desktop ---

    property bool anchorLeft: true
    property bool anchorRight: false
    // Position of the bar in the window: 0 = at the left edge, 1 = at the right edge
    property real barAlign: 0
    property string phase: ""
    property int cycle: 0
    readonly property bool paused: sequence.paused

    readonly property string anchorsText: {
        const edges = ["TOP", "BOTTOM"]
        if (anchorLeft)
            edges.push("LEFT")
        if (anchorRight)
            edges.push("RIGHT")
        return edges.join(" | ")
    }

    function step(name) {
        phase = name
        console.log("[Experimental]", new Date().toISOString().slice(11, 23), "cycle", cycle,
                    "|", name, "| anchors:", anchorsText, "| width:", width)
    }

    function togglePause() {
        sequence.paused = !sequence.paused
        console.log("[Experimental]", sequence.paused ? "paused" : "resumed")
    }

    width: dockWidth
    height: Screen.height
    // The tint is drawn by an item: a translucent window color is not premultiplied by Qt
    // and the compositor would show it almost opaque and too bright
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: true

    LayerShell.Window.scope: "experimental-dock"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | (anchorLeft ? LayerShell.Window.AnchorLeft : 0)
                               | (anchorRight ? LayerShell.Window.AnchorRight : 0)
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // Translucent tint, shows the area of the window
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.15, 0.55, 1.0, 0.22)
    }

    // --- State of the experiment ---

    // Kept at the top center of the screen. It is a part of this window (one window per
    // process keeps the animations smooth), so it is visible only while the window covers
    // the center of the screen.
    Rectangle {
        id: statusPanel

        readonly property bool clientProcess: Qt.application.arguments.indexOf("client") >= 0
        // Position of the window on the screen: at the left edge unless anchored right only
        readonly property real windowScreenX: window.anchorLeft ? 0 : window.fullWidth - window.width

        x: Math.round((window.fullWidth - width) / 2 - windowScreenX)
        y: 60
        width: 640
        height: status.implicitHeight + 32
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.55)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Column {
            id: status

            anchors.centerIn: parent
            spacing: 6

            Text {
                text: "Experimental: moving the bar across the screen"
                color: "#9aa4b8"
                font.pixelSize: 14
            }
            Text {
                text: window.phase + (window.paused ? "   [PAUSED]" : "")
                color: window.paused ? "#ffd166" : "white"
                font.pixelSize: 24
                font.bold: true
            }
            Text {
                text: "anchors: " + window.anchorsText
                color: "#ff6b6b"
                font.pixelSize: 16
                font.family: "monospace"
            }
            Text {
                text: "window width: " + window.width + " px   cycle: " + window.cycle
                color: "white"
                font.pixelSize: 16
                font.family: "monospace"
            }
            Text {
                text: statusPanel.clientProcess ? "running in a client process (MProxyWindow)"
                                               : "running in the server process"
                color: "#6bcb77"
                font.pixelSize: 13
                font.family: "monospace"
            }
            Text {
                text: "Click the bar to pause / resume"
                color: "#9aa4b8"
                font.pixelSize: 13
            }
        }
    }

    // --- The bar ---

    Rectangle {
        id: bar

        x: window.barMargin + window.barAlign * (window.width - window.barWidth - 2 * window.barMargin)
        y: window.barMargin
        width: window.barWidth
        height: window.height - 2 * window.barMargin
        radius: 18
        color: window.paused ? "#5a4a1e" : "#2b303b"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)

        // Placeholders of dock buttons, they make the motion easy to follow
        Column {
            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: ["#ff6b6b", "#ffd93d", "#6bcB77", "#4d96ff", "#c77dff", "#f8f9fa"]

                delegate: Rectangle {
                    required property string modelData

                    width: 44
                    height: 44
                    radius: 12
                    color: modelData
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: window.togglePause()
        }
    }

    // --- Markers of the anchored side edges ---

    Rectangle {
        anchors.left: parent.left
        width: 4
        height: parent.height
        color: "red"
        visible: window.anchorLeft
    }

    Rectangle {
        anchors.right: parent.right
        width: 4
        height: parent.height
        color: "red"
        visible: window.anchorRight
    }

    // --- The sequence ---

    SequentialAnimation {
        id: sequence

        running: true
        loops: Animation.Infinite

        // From the left edge to the right one

        ScriptAction { script: { window.cycle++; window.step("L→R 1/8: expanding to the full width") } }
        NumberAnimation { target: window; property: "width"; to: window.fullWidth; duration: window.resizeDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("L→R 2/8: full width, waiting") }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: { window.anchorRight = true; window.step("L→R 3/8: right edge anchored") } }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: window.step("L→R 4/8: moving the bar to the right") }
        NumberAnimation { target: window; property: "barAlign"; to: 1; duration: window.moveDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("L→R 5/8: bar at the right edge, waiting") }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: { window.anchorLeft = false; window.step("L→R 6/8: left edge released") } }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: window.step("L→R 7/8: shrinking to the dock width") }
        NumberAnimation { target: window; property: "width"; to: window.dockWidth; duration: window.resizeDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("L→R 8/8: docked at the right edge, waiting") }
        PauseAnimation { duration: window.pauseDuration }

        // From the right edge back to the left one

        ScriptAction { script: window.step("R→L 1/8: expanding to the full width") }
        NumberAnimation { target: window; property: "width"; to: window.fullWidth; duration: window.resizeDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("R→L 2/8: full width, waiting") }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: { window.anchorLeft = true; window.step("R→L 3/8: left edge anchored") } }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: window.step("R→L 4/8: moving the bar to the left") }
        NumberAnimation { target: window; property: "barAlign"; to: 0; duration: window.moveDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("R→L 5/8: bar at the left edge, waiting") }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: { window.anchorRight = false; window.step("R→L 6/8: right edge released") } }
        PauseAnimation { duration: window.pauseDuration }

        ScriptAction { script: window.step("R→L 7/8: shrinking to the dock width") }
        NumberAnimation { target: window; property: "width"; to: window.dockWidth; duration: window.resizeDuration; easing.type: Easing.InOutSine }

        ScriptAction { script: window.step("R→L 8/8: docked at the left edge, waiting") }
        PauseAnimation { duration: window.pauseDuration }
    }
}
