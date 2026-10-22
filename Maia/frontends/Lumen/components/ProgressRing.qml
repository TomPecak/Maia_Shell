import QtQuick
import QtQuick.Shapes

import LumenFrontend

// Circular progress: a faint track and an arc in the accent color, starting at the top
// and running clockwise. value is 0..1.
Item {
    id: ring

    property real value: 1
    property real thickness: 4
    property color color: Theme.accent
    property color trackColor: Theme.controlStrong

    readonly property real radius: (Math.min(width, height) - thickness) / 2

    implicitWidth: 64
    implicitHeight: 64

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.trackColor
            strokeWidth: ring.thickness

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.value > 0.001 ? ring.color : "transparent"
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap

            Behavior on strokeColor { ColorAnimation { duration: Theme.durationNormal } }

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: -90
                sweepAngle: 360 * Math.max(0, Math.min(1, ring.value))
            }
        }
    }
}
