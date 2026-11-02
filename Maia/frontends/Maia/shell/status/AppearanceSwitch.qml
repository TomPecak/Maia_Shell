pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import Maia.Backend as Maia
import MaiaFrontend

// Light / dark switch for testing the appearance: a segmented control of iPadOS with a sun and a
// moon. Both states are visible at once and the thumb shows the current one, so it reads as a
// state, not as an action. Horizontal or vertical, following the dock (StatusArea.qml).
Item {
    id: control

    property bool vertical: false

    readonly property real segment: 36
    readonly property real inset: 3

    width: vertical ? segment + 2 * inset : 2 * segment + 2 * inset
    height: vertical ? 2 * segment + 2 * inset : segment + 2 * inset

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Appearance")

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
