import QtQuick

import ".."

// Logo of the start button: four circles of light in tones of the accent color,
// the top-left one is larger and brighter (the "source" of the light)
Item {
    id: glyph

    property int size: 22

    implicitWidth: size
    implicitHeight: size

    Repeater {
        // Center (cx, cy) and diameter (d) relative to the size, opacity of the tone
        model: [
            { cx: 0.27, cy: 0.27, d: 0.50, tone: 1.0 },
            { cx: 0.76, cy: 0.25, d: 0.40, tone: 0.8 },
            { cx: 0.25, cy: 0.76, d: 0.40, tone: 0.8 },
            { cx: 0.76, cy: 0.76, d: 0.40, tone: 0.6 }
        ]

        delegate: Rectangle {
            required property var modelData

            width: glyph.size * modelData.d
            height: width
            radius: width / 2
            x: glyph.size * modelData.cx - width / 2
            y: glyph.size * modelData.cy - height / 2
            color: Theme.accent
            opacity: modelData.tone
            antialiasing: true

            Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
        }
    }
}
