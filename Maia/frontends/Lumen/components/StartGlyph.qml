import QtQuick

import ".."

// Logo of the start button: four rounded tiles in tones of the accent color
Item {
    id: glyph

    property int size: 22

    implicitWidth: size
    implicitHeight: size

    Grid {
        anchors.fill: parent
        columns: 2
        spacing: Math.round(glyph.size * 0.09)

        Repeater {
            model: [1.0, 0.82, 0.82, 0.64]

            delegate: Rectangle {
                required property real modelData

                width: (glyph.size - parent.spacing) / 2
                height: width
                radius: width * 0.22
                color: Theme.accent
                opacity: modelData

                Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
            }
        }
    }
}
