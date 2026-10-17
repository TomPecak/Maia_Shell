pragma ComponentBehavior: Bound

import QtQuick

import ".."

// Logo of the start button: four circles of light in tones of the accent color,
// the top-left one is larger and brighter (the "source" of the light).
//
// When the start menu is open (active), the large circle shrinks to the size of the others
// and all circles light up to the full accent tone.
Item {
    id: glyph

    property int size: 22
    // The start menu is open
    property bool active: false

    // Center and diameter of the top-left circle, relative to the size
    property real leadCenter: active ? 0.25 : 0.27
    property real leadDiameter: active ? 0.40 : 0.50

    implicitWidth: size
    implicitHeight: size

    Behavior on leadCenter { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
    Behavior on leadDiameter { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }

    Dot { cx: glyph.leadCenter; cy: glyph.leadCenter; diameter: glyph.leadDiameter; tone: 1.0 }
    Dot { cx: 0.76; cy: 0.25; tone: 0.8 }
    Dot { cx: 0.25; cy: 0.76; tone: 0.8 }
    Dot { cx: 0.76; cy: 0.76; tone: 0.6 }

    // Circle with the center (cx, cy) and diameter relative to the size, tone is the opacity
    // of the accent color while the start menu is closed
    component Dot: Rectangle {
        property real cx
        property real cy
        property real diameter: 0.40
        property real tone: 1.0

        width: glyph.size * diameter
        height: width
        radius: width / 2
        x: glyph.size * cx - width / 2
        y: glyph.size * cy - height / 2
        color: Theme.accent
        opacity: glyph.active ? 1.0 : tone
        antialiasing: true

        Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
        Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
    }
}
