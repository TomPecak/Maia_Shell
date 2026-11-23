import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

import MaiaFrontend

// How far a job is, as a ring: its share, a glyph when it is paused, done or failed.
//
// Redrawn only when the whole percent changes, and never animated in between: a copy of many minutes
// must not keep the screen rendering at 60 frames a second. For the same reason a job that does not
// tell its share has a still piece of the ring here (the card, seen only on demand, has a moving one).
Item {
    id: ring

    // 0 .. 100, -1 unknown
    property int percent: -1
    // NotificationCenter.JobState: 0 running, 1 paused, 2 finished, 3 failed
    property int jobState: 0
    property real lineWidth: 3

    readonly property color tint: jobState === 2 ? Theme.green
                                : jobState === 3 ? Theme.red
                                : jobState === 1 ? Theme.secondaryLabel
                                : Theme.accent
    // A finished or failed job is a closed ring
    readonly property real share: jobState >= 2 ? 1 : percent >= 0 ? Math.min(100, percent) / 100 : 0.25
    readonly property string glyph: jobState === 2 ? "checkmark-symbolic"
                                  : jobState === 3 ? "window-close-symbolic"
                                  : jobState === 1 ? "media-playback-pause-symbolic"
                                  : ""

    implicitWidth: 28
    implicitHeight: 28

    Shape {
        id: shape

        readonly property real radius: (Math.min(ring.width, ring.height) - ring.lineWidth) / 2

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.fill
            strokeWidth: ring.lineWidth

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: shape.radius
                radiusY: shape.radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.tint
            strokeWidth: ring.lineWidth
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: shape.radius
                radiusY: shape.radius
                startAngle: -90
                sweepAngle: 360 * ring.share
            }
        }
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Math.round(ring.width * 0.46)
        height: width
        visible: ring.glyph.length > 0
        source: visible ? Qt.resolvedUrl("../../assets/icons/" + ring.glyph + ".svg") : ""
        isMask: true
        color: ring.tint
    }
}
