import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// The tall slider of the Control Center of iPadOS (brightness, volume): the module itself is the
// track, the level a white fill rising from the bottom, the glyph near the bottom. Dragging moves
// the level by the distance moved (it does not jump to the pointer, as in iPadOS), a click sets
// it where the pointer is, the wheel and the arrow keys move it in steps. A click on the glyph
// without moving runs glyphClicked (mute for the volume).
ModulePlatter {
    id: slider

    property string title
    property url icon
    // 0..1
    property real value: 0

    // The user moved it
    signal moved(real value)
    signal glyphClicked()

    highlighted: area.containsMouse

    activeFocusOnTab: true
    Keys.onUpPressed: slider.moved(Math.min(1, value + 0.05))
    Keys.onDownPressed: slider.moved(Math.max(0, value - 0.05))

    Accessible.role: Accessible.Slider
    Accessible.name: title
    Accessible.onIncreaseAction: slider.moved(Math.min(1, value + 0.05))
    Accessible.onDecreaseAction: slider.moved(Math.max(0, value - 0.05))

    // The level, inside the rounded module: the bottom corners are the module's, the top ones
    // become the module's as the level reaches the top (clip would cut a rectangle, not the rounding)
    Rectangle {
        id: level

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: slider.border.width
        height: Math.round((slider.height - 2 * slider.border.width) * Math.max(0, Math.min(1, slider.value)))
        color: Theme.sliderFill
        readonly property real cornerRadius: slider.radius - slider.border.width
        bottomLeftRadius: cornerRadius
        bottomRightRadius: cornerRadius
        topLeftRadius: Math.max(0, cornerRadius - (slider.height - 2 * slider.border.width - height))
        topRightRadius: topLeftRadius

        Behavior on height {
            enabled: !area.pressed
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    Kirigami.Icon {
        id: glyph

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: 24
        height: 24
        source: slider.icon
        isMask: true
        color: Theme.sliderGlyph
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true

        property real startY: 0
        property real startValue: 0
        property bool dragged: false

        onPressed: function (mouse) {
            startY = mouse.y
            startValue = slider.value
            dragged = false
            slider.forceActiveFocus()
        }
        onPositionChanged: function (mouse) {
            if (!pressed)
                return
            if (Math.abs(mouse.y - startY) > 3)
                dragged = true
            if (dragged)
                slider.moved(Math.max(0, Math.min(1, startValue + (startY - mouse.y) / slider.height)))
        }
        onReleased: function (mouse) {
            if (dragged)
                return
            if (mouse.y > glyph.y - 8)
                slider.glyphClicked()
            else
                slider.moved(Math.max(0, Math.min(1, 1 - mouse.y / slider.height)))
        }
        onWheel: function (wheel) {
            const step = wheel.angleDelta.y > 0 ? 0.05 : wheel.angleDelta.y < 0 ? -0.05 : 0
            slider.moved(Math.max(0, Math.min(1, slider.value + step)))
        }
    }
}
