pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import Maia.Backend as Maia
import MaiaFrontend

// Light / dark switch for testing the appearance: a segmented control of iPadOS with a sun and a
// moon. Both states are visible at once and the thumb shows the current one, so it reads as a
// state, not as an action. Horizontal or vertical, following the dock.
//
// It belongs to the edge of the dock. When the dock moves to another edge, the switch does not
// travel across the screen (a small control crossing the windows would pull the eye away from
// the dock, which is the main movement): it quickly shrinks and fades out at its old place, and
// after a short pause appears at the new one with a soft spring, already in its new orientation.
// The parent positions it by placedEdge, which changes only while it is invisible.
Item {
    id: control

    // Edge of the dock the switch belongs to
    property int edge: Qt.TopEdge
    // Edge it is placed at now: follows edge while the switch is invisible
    property int placedEdge: Qt.TopEdge

    readonly property bool vertical: placedEdge === Qt.LeftEdge || placedEdge === Qt.RightEdge

    readonly property real segment: 36
    readonly property real inset: 3

    width: vertical ? segment + 2 * inset : 2 * segment + 2 * inset
    height: vertical ? 2 * segment + 2 * inset : segment + 2 * inset

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Appearance")

    // At start it simply is where it belongs
    Component.onCompleted: {
        placedEdge = edge
        d.ready = true
    }

    onEdgeChanged: {
        if (!d.ready) {
            placedEdge = edge
            return
        }
        // Started again when the edge changes once more while it moves: it disappears from
        // wherever it is and comes up at the newest edge
        moveAnimation.restart()
    }

    QtObject {
        id: d

        property bool ready: false
        // Scale it shrinks to and grows from
        readonly property real hiddenScale: 0.6
    }

    SequentialAnimation {
        id: moveAnimation

        // Leaving: short and accelerating, it is going away
        ParallelAnimation {
            ScaleAnimator { target: control; to: d.hiddenScale; duration: 150; easing.type: Easing.InCubic }
            OpacityAnimator { target: control; to: 0; duration: 150; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: control.placedEdge = control.edge
        }
        // A beat between leaving and arriving, so the appearance reads as one at the new place
        PauseAnimation { duration: 90 }
        // Arriving: a spring with a small overshoot, the opacity a little ahead of the size
        ParallelAnimation {
            ScaleAnimator {
                target: control
                from: d.hiddenScale
                to: 1
                duration: 420
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
            OpacityAnimator { target: control; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
    }

    RectangularShadow {
        anchors.fill: track
        radius: track.radius
        offset.y: 2
        blur: 12
        color: Qt.rgba(0, 0, 0, 0.18)
    }

    Rectangle {
        id: track

        anchors.fill: parent
        radius: 11
        color: Theme.dock
        border.width: 1
        border.color: Theme.hairline

        Behavior on color {
            ColorAnimation { duration: Theme.modeChangeDuration }
        }
    }

    // Marks the current mode, slides to the other segment
    Rectangle {
        id: thumb

        readonly property real offset: Theme.dark ? control.segment : 0

        x: control.inset + (control.vertical ? 0 : offset)
        y: control.inset + (control.vertical ? offset : 0)
        width: control.segment
        height: control.segment
        radius: 8
        color: Theme.segmentThumb

        Behavior on x {
            XAnimator { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
        Behavior on y {
            YAnimator { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
        Behavior on color {
            ColorAnimation { duration: Theme.modeChangeDuration }
        }
    }

    Repeater {
        model: [false, true]

        Item {
            id: segmentItem

            required property bool modelData
            required property int index
            readonly property bool current: Theme.dark === modelData

            x: control.inset + (control.vertical ? 0 : index * control.segment)
            y: control.inset + (control.vertical ? index * control.segment : 0)
            width: control.segment
            height: control.segment

            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData ? qsTr("Dark") : qsTr("Light")
            Accessible.checked: current
            Accessible.onPressAction: Theme.setDark(modelData)

            Canvas {
                id: glyph

                readonly property color ink: segmentItem.current ? Theme.label : Theme.secondaryLabel

                anchors.centerIn: parent
                width: 20
                height: 20
                scale: segmentArea.pressed ? 0.85 : 1

                onInkChanged: requestPaint()

                Behavior on scale {
                    ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = ink
                    ctx.strokeStyle = ink
                    const c = width / 2
                    if (segmentItem.modelData) {
                        // Moon: a disc with a disc cut out of its upper right part
                        ctx.beginPath()
                        ctx.arc(c, c, 7.5, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.globalCompositeOperation = "destination-out"
                        ctx.beginPath()
                        ctx.arc(c + 4.5, c - 3.5, 6.5, 0, 2 * Math.PI)
                        ctx.fill()
                    } else {
                        // Sun: a disc and eight rays
                        ctx.beginPath()
                        ctx.arc(c, c, 4, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.lineWidth = 1.8
                        ctx.lineCap = "round"
                        for (let i = 0; i < 8; ++i) {
                            const angle = i * Math.PI / 4
                            ctx.beginPath()
                            ctx.moveTo(c + Math.cos(angle) * 6.8, c + Math.sin(angle) * 6.8)
                            ctx.lineTo(c + Math.cos(angle) * 9, c + Math.sin(angle) * 9)
                            ctx.stroke()
                        }
                    }
                }
            }

            MouseArea {
                id: segmentArea

                anchors.fill: parent
                onClicked: Theme.setDark(segmentItem.modelData)
            }
        }
    }

    Maia.MaskArea {
        anchors.fill: parent
    }
}
