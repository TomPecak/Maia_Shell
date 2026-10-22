pragma ComponentBehavior: Bound

import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

// Experimental: test bench of Maia Shell for the layer-shell behavior.
//
// The desktop (this window, background layer, server process) shows a grid, which makes
// jumps and glitches easy to notice, and a switcher of the frontends.
// The experiment itself is in ExperimentWindow.qml (top layer), it runs in a separate
// client process started by MProxyWindow, together with the panel showing its state.
Window {
    id: desktop

    width: Screen.width
    height: Screen.height
    color: "#14161c"
    flags: Qt.FramelessWindowHint
    visible: true
    title: "Experimental"

    LayerShell.Window.scope: "experimental-desktop"
    LayerShell.Window.layer: LayerShell.Window.LayerBackground
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // --- Grid, a line every 100 px ---

    Repeater {
        model: Math.ceil(desktop.width / 100)

        delegate: Rectangle {
            required property int index

            x: index * 100
            width: 1
            height: desktop.height
            color: index % 5 === 0 ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
        }
    }

    Repeater {
        model: Math.ceil(desktop.height / 100)

        delegate: Rectangle {
            required property int index

            y: index * 100
            width: desktop.width
            height: 1
            color: index % 5 === 0 ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
        }
    }

    // --- Frontend switcher ---

    MFrontendModel {
        id: frontends
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        spacing: 8

        Repeater {
            model: frontends

            delegate: Rectangle {
                id: frontendButton

                required property string frontendId
                required property string frontendName
                required property bool frontendActive

                width: label.implicitWidth + 32
                height: 36
                radius: 8
                color: frontendActive ? "#4d96ff"
                     : mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: frontendButton.frontendName
                    color: "white"
                    font.pixelSize: 14
                }

                MouseArea {
                    id: mouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (!frontendButton.frontendActive)
                            frontends.setActiveFrontend(frontendButton.frontendId)
                    }
                }
            }
        }
    }

    // The experiment runs in a separate process. The client process gets the geometry of
    // this item once, at its start: the width of the dock and the height of the screen.
    MProxyWindow {
        id: experiment

        source: "ExperimentWindow.qml"
        proxyVisible: true
        anchors.left: parent.left
        anchors.top: parent.top
        width: 96
        height: desktop.height
        swapInterval: 1
    }
}
