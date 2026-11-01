import QtQuick

import MaiaFrontend

// Icon of the App Library button in the dock: four small rounded squares, like the App Library
// icon of iPadOS (there they are miniatures of app icons). Fills the size it is given.
Item {
    id: glyph

    readonly property real side: Math.min(width, height)
    readonly property real gap: side * 0.12
    readonly property real square: (side - gap) / 2

    Grid {
        anchors.centerIn: parent
        columns: 2
        spacing: glyph.gap

        Repeater {
            model: [Theme.blue, Theme.green, Theme.orange, Theme.pink]

            Rectangle {
                required property color modelData

                width: glyph.square
                height: glyph.square
                radius: width * 0.28
                color: modelData
            }
        }
    }
}
