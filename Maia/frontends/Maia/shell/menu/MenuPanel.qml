import QtQuick
import QtQuick.Effects

// Menu surface in the style of iPadOS: an opaque light material (no blur: blurring the wallpaper
// behind the panel showed artefacts along the edges), large corner radius and a soft wide shadow.
// The items (MenuItem, MenuSeparator) are stacked in a column.
//
// It opens with a springy zoom out of transformOrigin (the corner at the click point) and closes
// with a short shrink and fade. While a submenu covers it, it is pushed back (shrunk and dimmed).
// All animations are Animators: they run in the render thread, so a busy GUI thread does not
// make them stutter.
Item {
    id: panel

    default property alias content: column.data
    property bool open: false
    // Scale the panel grows from
    property real closedScale: 0.5
    // A submenu lies over the panel
    property bool pushedBack: false

    readonly property int radius: 14
    readonly property int padding: 6
    readonly property bool hovered: hoverHandler.hovered

    implicitWidth: 260
    implicitHeight: column.implicitHeight + 2 * padding
    width: implicitWidth
    height: implicitHeight

    // Shown from opening until the closing animation has finished. Animators write opacity only
    // when they finish, so the visibility cannot follow the opacity; it cannot follow
    // closeAnimation.running either: when open turns false that binding is evaluated before the
    // animation starts, the panel (and the menu window) would vanish at once and KWin would play
    // its own closing effect of the window instead.
    property bool shown: false

    visible: shown
    opacity: 0
    scale: closedScale

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
        shown = true
        closeAnimation.stop()
        openAnimation.restart()
    }

    ParallelAnimation {
        id: openAnimation

        // Spring like: a fast start with a small overshoot
        ScaleAnimator {
            target: panel
            from: panel.closedScale
            to: 1
            duration: 420
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
        }
        OpacityAnimator {
            target: panel
            from: 0
            to: 1
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: closeAnimation

        // Not when it was stopped because the panel opened again
        onFinished: panel.shown = panel.open

        ScaleAnimator {
            target: panel
            to: 0.85
            duration: 180
            easing.type: Easing.InCubic
        }
        OpacityAnimator {
            target: panel
            to: 0
            duration: 180
            easing.type: Easing.InCubic
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // Everything the panel shows; shrinks around its centre while a submenu covers the panel
    Item {
        id: body

        anchors.fill: parent
        scale: panel.pushedBack ? 0.96 : 1

        Behavior on scale {
            ScaleAnimator { duration: 260; easing.type: Easing.OutCubic }
        }

        RectangularShadow {
            anchors.fill: parent
            radius: panel.radius
            offset.y: 12
            blur: 48
            spread: 0
            color: Qt.rgba(0, 0, 0, 0.22)
        }

        // The material: the light cool grey of iPadOS 18 (#F2F2F7, its system grey for opaque
        // surfaces). Menus of iPadOS have no visible edge, the shadow sets them apart; the faint
        // hairline only keeps the outline crisp on a very light wallpaper.
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            color: "#f2f2f7"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.05)
        }

        // Clicks on the padding and separators do not fall through the menu
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Column {
            id: column

            y: panel.padding
            width: panel.width
        }

        // Dimming while a submenu lies over the panel
        Rectangle {
            anchors.fill: parent
            radius: panel.radius
            color: Qt.rgba(0, 0, 0, 0.12)
            opacity: panel.pushedBack ? 1 : 0

            Behavior on opacity {
                OpacityAnimator { duration: 260; easing.type: Easing.OutCubic }
            }
        }
    }
}
