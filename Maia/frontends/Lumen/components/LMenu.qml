import QtQuick
import QtQuick.Effects

import ".."

// Fluent style menu surface: a rounded acrylic card with a soft shadow, the items
// (LMenuItem, LMenuSeparator) are stacked in a column. It opens with a short slide and
// fade (decelerating) and closes with a quick fade (accelerating).
Item {
    id: menu

    default property alias content: column.data
    property bool open: false
    // The menu opens upwards from the click point, so it slides in from below
    property bool openUpwards: false
    // Opening progress 0..1, drives the animation
    property real progress: 0

    readonly property int padding: Theme.spacingXS
    readonly property bool hovered: hoverHandler.hovered
    // Item (or separator) under the mouse, also a disabled one
    readonly property Item hoveredItem: hoverHandler.hovered
                                        ? column.childAt(hoverHandler.point.position.x,
                                                         hoverHandler.point.position.y - padding)
                                        : null

    implicitWidth: 256
    implicitHeight: column.implicitHeight + 2 * padding
    width: implicitWidth
    height: implicitHeight

    visible: progress > 0
    opacity: progress
    transform: Translate {
        y: (menu.openUpwards ? 1 : -1) * Theme.spacingM * (1 - menu.progress)
    }

    onOpenChanged: animate()

    // Plays the opening animation from the start, e.g. after the menu moved to a new position
    function replay() {
        if (!open)
            return
        progress = 0
        animate()
    }

    function animate() {
        animation.stop()
        animation.to = open ? 1 : 0
        animation.duration = open ? Theme.durationNormal : Theme.durationFast
        animation.easing.type = open ? Theme.easingEnter : Theme.easingExit
        animation.start()
    }

    HoverHandler {
        id: hoverHandler
    }

    NumberAnimation {
        id: animation

        target: menu
        property: "progress"
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        offset.y: 8
        blur: 24
        spread: 0
        color: Theme.shadow
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.stroke

        // Clicks on the padding and separators do not fall through the menu
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Column {
        id: column

        x: 0
        y: menu.padding
        width: menu.width
    }
}
