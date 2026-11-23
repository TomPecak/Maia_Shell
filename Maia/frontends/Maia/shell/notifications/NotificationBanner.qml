pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import MaiaFrontend

// A notification as a banner at the top of the screen, as on iPadOS: a NotificationCard with the way
// a banner moves.
//
//   tap             the default action (without one: expands)
//   swipe up        away; the notification stays in the list
//   pull down,
//   long press      expands
//
// Only shows data and says what was asked: BannerWindow.qml talks to the notification center.
//
// Performance: the banner moves on the render thread (Animators on `mover`), so its movement does
// not depend on the GUI thread; the root item never moves, so the input mask of the window does
// not change while it does.
Item {
    id: banner

    property alias appName: card.appName
    property alias appIcon: card.appIcon
    property alias desktopEntry: card.desktopEntry
    property alias title: card.title
    property alias body: card.body
    property alias time: card.time
    property alias image: card.image
    property alias actions: card.actions
    property alias actionIcons: card.actionIcons
    property alias files: card.files
    property alias hasDefaultAction: card.hasDefaultAction
    property alias inlineReply: card.inlineReply
    property alias replyPlaceholder: card.replyPlaceholder
    property alias replySubmitText: card.replySubmitText
    property alias urgency: card.urgency
    property alias originName: card.originName
    property alias waiting: card.waiting
    property alias maximumBodyHeight: card.maximumBodyHeight
    property alias expanded: card.expanded
    property alias replyOpen: card.replyOpen
    // The window has its first frame: the banner may come in (so that no frame of it is lost)
    property bool ready: true

    readonly property alias critical: card.critical
    readonly property alias replying: card.replyOpen
    readonly property alias canExpand: card.canExpand
    readonly property alias wantsKeyboard: card.wantsKeyboard
    readonly property bool leaving: d.leaving
    // The user is busy with it: its time stands still
    readonly property bool held: card.hovered || tap.pressed || swipe.active || card.expanded || card.replyOpen
                                 || card.dragging

    signal swipedAway()
    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string key)
    signal replied(string text)
    signal fileOpened(string url)
    // The way out has ended (leave())
    signal leaveFinished()

    // Out, on the render thread. replaced: another banner comes in its place, so this one sinks
    // behind it instead of crossing it on the way up
    function leave(replaced) {
        if (d.leaving)
            return
        d.leaving = true
        enter.stop()
        snapBack.stop()
        if (!d.entered) {
            banner.leaveFinished()
            return
        }
        if (replaced)
            sink.start()
        else
            rise.start()
    }

    function setExpanded(value) {
        card.setExpanded(value)
    }

    function openReply() {
        card.openReply()
    }

    implicitHeight: card.targetHeight
    height: implicitHeight

    onReadyChanged: d.comeIn()
    Component.onCompleted: d.comeIn()

    QtObject {
        id: d

        property bool leaving: false
        property bool entered: false
        readonly property int offScreen: mover.height + 24
        // A swipe this far goes away, whatever the banner's height: it starts near the top edge
        // of the screen, so there is little room for the finger or the pointer
        readonly property int swipeAway: 32
        // A pull this far (after its resistance) expands
        readonly property int expandPull: 30

        function comeIn() {
            if (!banner.ready || entered || leaving)
                return
            entered = true
            enter.start()
        }

        // Up follows the finger, down resists: a banner has nowhere to go there
        function pulled(distance) {
            return distance < 0 ? distance : Math.min(distance * 0.4, 48)
        }

        function released(velocity) {
            const distance = mover.y
            if (distance < -d.swipeAway || (velocity < -400 && distance < -8)) {
                banner.swipedAway()
                return
            }
            if (distance >= expandPull && !banner.expanded)
                banner.setExpanded(true)
            snapBack.start()
        }
    }

    // --- What moves: the plate and its shadow together ---

    Item {
        id: mover

        width: banner.width
        height: card.targetHeight
        opacity: 0
        scale: tap.pressed && !swipe.active ? 0.98 : 1

        Behavior on height {
            enabled: d.entered && !d.leaving

            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }

        RectangularShadow {
            anchors.fill: card
            offset.y: 6
            blur: 24
            radius: card.radius
            color: Theme.shadow
        }

        NotificationCard {
            id: card

            objectName: "bannerPlate"
            anchors.fill: parent

            onDismissed: banner.dismissed()
            onActionInvoked: key => banner.actionInvoked(key)
            onReplied: text => banner.replied(text)
            onFileOpened: url => banner.fileOpened(url)

            TapHandler {
                id: tap

                longPressThreshold: 0.45
                enabled: !banner.leaving
                cursorShape: Qt.PointingHandCursor
                onTapped: {
                    if (banner.hasDefaultAction)
                        banner.defaultInvoked()
                    else if (banner.canExpand && !banner.expanded)
                        banner.setExpanded(true)
                }
                onLongPressed: {
                    if (banner.canExpand)
                        banner.setExpanded(true)
                }
            }

            DragHandler {
                id: swipe

                target: null
                xAxis.enabled: false
                enabled: !banner.leaving && !banner.replying
                onActiveChanged: {
                    if (active) {
                        enter.complete()
                        snapBack.stop()
                    } else {
                        d.released(centroid.velocity.y)
                    }
                }
                onActiveTranslationChanged: {
                    if (active)
                        mover.y = d.pulled(activeTranslation.y)
                }
            }
        }
    }

    // --- Movement, all of it on the render thread ---

    ParallelAnimation {
        id: enter

        YAnimator {
            target: mover
            from: -d.offScreen
            to: 0
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
        }
        OpacityAnimator {
            target: mover
            from: 0
            to: 1
            duration: 160
            easing.type: Easing.OutQuad
        }
    }

    YAnimator {
        id: snapBack

        target: mover
        to: 0
        duration: 260
        easing.type: Easing.OutBack
        easing.overshoot: 0.8
    }

    SequentialAnimation {
        id: rise

        ParallelAnimation {
            YAnimator {
                target: mover
                to: -d.offScreen
                duration: 220
                easing.type: Easing.InCubic
            }
            OpacityAnimator {
                target: mover
                to: 0
                duration: 220
                easing.type: Easing.InQuad
            }
        }
        ScriptAction {
            script: banner.leaveFinished()
        }
    }

    SequentialAnimation {
        id: sink

        ParallelAnimation {
            ScaleAnimator {
                target: mover
                to: 0.92
                duration: 200
                easing.type: Easing.OutCubic
            }
            OpacityAnimator {
                target: mover
                to: 0
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
        ScriptAction {
            script: banner.leaveFinished()
        }
    }
}
