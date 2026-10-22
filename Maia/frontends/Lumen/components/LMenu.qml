import QtQuick
import QtQuick.Effects

import LumenFrontend

// Fluent style menu surface: a rounded acrylic card with a soft shadow, the items
// (LMenuItem, LMenuSeparator) are stacked in a column. It opens with a short slide and
// fade (decelerating) and closes with a quick fade (accelerating).
//
// The slide and fade run as Animators on the render thread, in sync with the frames of the
// window (smooth also when the GUI thread is busy or the process has several windows).
// While an Animator runs, the animated properties keep their old values on the GUI side,
// so the visibility of the menu is controlled explicitly, not derived from the opacity.
Item {
    id: menu

    default property alias content: column.data
    property bool open: false
    // The menu opens upwards from the click point, so it slides in from below
    property bool openUpwards: false

    readonly property int padding: Theme.spacingXS
    readonly property bool hovered: hoverHandler.hovered
    // Item (or separator) under the mouse, also a disabled one
    readonly property Item hoveredItem: hoverHandler.hovered
                                        ? column.childAt(hoverHandler.point.position.x,
                                                         hoverHandler.point.position.y - padding)
                                        : null
    // Distance the menu travels while opening
    readonly property real enterOffset: (openUpwards ? 1 : -1) * Theme.spacingM

    implicitWidth: 256
    implicitHeight: column.implicitHeight + 2 * padding
    width: implicitWidth
    height: implicitHeight
    visible: false

    onOpenChanged: {
        if (open) {
            replay()
        } else {
            openAnimation.stop()
            closeAnimation.restart()
        }
    }

    // Plays the opening animation from the start, e.g. after the menu moved to a new position
    function replay() {
        if (!open)
            return
        openAnimation.stop()
        closeAnimation.stop()
        body.opacity = 0
        body.y = enterOffset
        visible = true
        openAnimation.restart()
    }

    ParallelAnimation {
        id: openAnimation

        OpacityAnimator {
            target: body
            to: 1
            duration: Theme.durationNormal
            easing.type: Theme.easingEnter
        }
        YAnimator {
            target: body
            to: 0
            duration: Theme.durationNormal
            easing.type: Theme.easingEnter
        }
    }

    ParallelAnimation {
        id: closeAnimation

        OpacityAnimator {
            target: body
            to: 0
            duration: Theme.durationFast
            easing.type: Theme.easingExit
        }
        YAnimator {
            target: body
            to: menu.enterOffset
            duration: Theme.durationFast
            easing.type: Theme.easingExit
        }

        onFinished: {
            if (!menu.open)
                menu.visible = false
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // Animated part of the menu
    Item {
        id: body

        width: menu.width
        height: menu.height
        opacity: 0

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
}
