import QtQuick
import QtQuick.Effects
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import LumenFrontend

// Base of the flyouts (start menu, calendar, quick settings, widgets).
//
// A flyout is a layer-shell window anchored to screen edges. The taskbar reserves its area
// (exclusion zone), so the compositor places a flyout anchored to the bottom edge right above
// the taskbar. The window is a bit larger than the visible card, the margin holds the shadow
// and does not receive input (MaskArea).
//
// The flyout is open while Shell.activeFlyout equals flyoutName. It opens with a slide and fade
// (decelerating) and closes faster (accelerating); it closes on Escape and when it loses
// the keyboard focus (click into another window).
//
// The slide and fade run as Animators on the render thread, in sync with the frames of the
// window. While an Animator runs, the animated properties keep their old values on the GUI
// side, so the visibility of the window is controlled explicitly at the end of the animations.
//
// The window keeps a fixed size (windowCardHeight), the card inside may be smaller and
// change its height with an animation (cardHeight), without resizing the Wayland surface.
Window {
    id: flyout

    // Name used in Shell.activeFlyout
    required property string flyoutName
    property int cardWidth: 360
    // Height of the visible card, may change while the flyout is open
    property int cardHeight: 480
    // Height reserved by the window for the card (the largest height of the card)
    property int windowCardHeight: cardHeight
    // The card fills the window height, e.g. when the window is anchored to the top and bottom edges
    property bool stretchCard: false
    // Screen edges the window is anchored to (LayerShell.Window.Anchor* flags)
    property int edges: LayerShell.Window.AnchorBottom
    // Direction the card comes from while opening
    property real enterOffsetX: 0
    property real enterOffsetY: Theme.flyoutOffset
    // Margin around the card, holds the shadow
    property int shadowMargin: Theme.spacingM

    readonly property bool open: Shell.activeFlyout === flyoutName

    default property alias content: card.data

    // Called when the flyout has been opened, e.g. to focus a text field
    signal opened()

    width: cardWidth + 2 * shadowMargin
    height: windowCardHeight + 2 * shadowMargin
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: false

    LayerShell.Window.scope: "lumen-" + flyoutName
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: edges
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    onOpenChanged: {
        if (open) {
            visible = true
            d.hadFocus = false
            closeAnimation.stop()
            openAnimation.restart()
        } else {
            openAnimation.stop()
            closeAnimation.restart()
        }
    }

    // Close when the flyout loses the keyboard focus, e.g. after a click into an application
    onActiveChanged: {
        if (active) {
            d.hadFocus = true
        } else if (d.hadFocus && open) {
            d.hadFocus = false
            Shell.closeFlyouts()
        }
    }

    ParallelAnimation {
        id: openAnimation

        OpacityAnimator {
            target: motion
            to: 1
            duration: Theme.durationSlow
            easing.type: Theme.easingEnter
        }
        XAnimator {
            target: motion
            to: 0
            duration: Theme.durationSlow
            easing.type: Theme.easingEnter
        }
        YAnimator {
            target: motion
            to: 0
            duration: Theme.durationSlow
            easing.type: Theme.easingEnter
        }

        onFinished: {
            if (flyout.open)
                flyout.opened()
        }
    }

    ParallelAnimation {
        id: closeAnimation

        OpacityAnimator {
            target: motion
            to: 0
            duration: Theme.durationFast
            easing.type: Theme.easingExit
        }
        XAnimator {
            target: motion
            to: flyout.enterOffsetX
            duration: Theme.durationFast
            easing.type: Theme.easingExit
        }
        YAnimator {
            target: motion
            to: flyout.enterOffsetY
            duration: Theme.durationFast
            easing.type: Theme.easingExit
        }

        onFinished: {
            if (!flyout.open)
                flyout.visible = false
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: flyout.open
        onActivated: Shell.closeFlyouts()
    }

    Item {
        id: cardArea

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: flyout.shadowMargin
        height: flyout.stretchCard ? flyout.height - 2 * flyout.shadowMargin : flyout.cardHeight

        Behavior on height {
            enabled: !flyout.stretchCard && flyout.visible
            NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard }
        }

        // Animated part of the card: offset and transparent while closed
        Item {
            id: motion

            width: cardArea.width
            height: cardArea.height
            x: flyout.enterOffsetX
            y: flyout.enterOffsetY
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
                radius: Theme.radiusLarge
                color: Theme.surface
                border.width: 1
                border.color: Theme.stroke

                Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
            }
        }

        // Only the card receives input, the shadow margin lets it through. The mask covers
        // the final place of the card, it does not follow the opening animation.
        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    QtObject {
        id: d

        property bool hadFocus: false
    }
}
