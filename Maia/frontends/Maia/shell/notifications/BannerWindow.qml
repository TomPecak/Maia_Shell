pragma ComponentBehavior: Bound

import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia
import Maia.Notifications.Center
import Maia.Sounds
import Maia.Windows as Windows

import MaiaFrontend

// Notification banners at the top of the screen, in the middle, one at a time (iPadOS). What pops
// up and for how long is Maia.Notifications.Center's; this window only shows it.
//
// A newer notification does not wait for the time of the one on screen: after a moment it takes
// its place, and the older one stays in the list. A critical one stays until it is handled, and
// nothing replaces a banner the user is busy with.
//
// While the user works fullscreen on this screen only critical notifications pop up, the others go
// into the list. So the window can sit in the overlay layer, where a critical warning must be seen.
//
// The window exists only while it has a banner, so it costs nothing otherwise and never keeps a
// fullscreen window from being scanned out. Its size is fixed: a banner that grows needs no new
// buffers. Only the banner takes input (MaskArea). It never takes the keyboard by itself, only
// when the user has opened a banner that can be answered. exclusionZone 0 keeps it out of the dock's strip, wherever the dock is.
Window {
    id: bannerWindow

    readonly property int bannerWidth: Math.min(420, Screen.width - 32)
    // Room for the shadow around the banner
    readonly property int shadowMargin: 32
    readonly property int topMargin: 10
    // How long a banner is shown, at least, before a waiting one takes its place
    readonly property int minimumTime: 1500

    // The banner that is not on its way out
    property NotificationBanner current: null
    // Banners in the window, those on their way out too
    property int banners: 0
    // The window's first frame is on screen, so a banner coming in loses none of its movement
    property bool presented: false

    readonly property bool wantsKeyboard: current !== null && current.wantsKeyboard

    function open(url) {
        // Never through a shell; no spaces, as the command is split on them
        if (typeof backend !== "undefined" && backend)
            backend.runCommand("xdg-open " + url.replace(/ /g, "%20"))
    }

    width: bannerWidth + 2 * shadowMargin
    height: Math.min(Screen.height, 680)
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: popups.count > 0 || banners > 0

    LayerShell.Window.scope: "maia-notifications"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: wantsKeyboard ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                           : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false

    onVisibleChanged: presented = false

    // Emitted on the render thread, delivered to QML on this one; listened to only until it comes
    Connections {
        target: bannerWindow
        enabled: bannerWindow.visible && !bannerWindow.presented

        function onFrameSwapped() {
            bannerWindow.presented = true
        }
    }

    // The window the user works in is fullscreen on this screen
    Windows.FullscreenState {
        id: fullscreen

        screen: bannerWindow.screen
    }

    NotificationPopupsModel {
        id: popups

        maximumCount: 1
        suppressed: fullscreen.active || ShellState.notificationCenterOpen
        paused: bannerWindow.current !== null && bannerWindow.current.held

        // The sound the sender asked for, when its banner appears (a sender that plays its own, as
        // every KDE application through KNotification, asks for none or suppresses it)
        onPopupShown: (notificationId, soundName, soundFile, suppressSound) => {
            if (!suppressSound)
                Sounds.play(soundName, soundFile)
        }
    }

    // A newer notification takes the place of the one on screen
    Timer {
        interval: bannerWindow.minimumTime
        repeat: true
        running: popups.waiting > 0 && bannerWindow.current !== null
                 && !bannerWindow.current.held && !bannerWindow.current.critical
        onTriggered: bannerWindow.current.swipedAway()
    }

    ListView {
        id: list

        x: bannerWindow.shadowMargin
        y: bannerWindow.topMargin
        width: bannerWindow.bannerWidth
        height: bannerWindow.height - y
        interactive: false
        model: popups

        // No height of its own: a banner on its way out and the one taking its place lie in the
        // same spot. The way out is the delegate's own (delayRemove), with Animators, which a
        // view's transitions cannot use for a new item
        delegate: Item {
            id: slot

            required property var model

            width: list.width
            height: 0

            ListView.onRemove: {
                slot.ListView.delayRemove = true
                if (bannerWindow.current === banner)
                    bannerWindow.current = null
                banner.leave(popups.count > 0)
            }

            Component.onCompleted: {
                ++bannerWindow.banners
                bannerWindow.current = banner
            }
            Component.onDestruction: --bannerWindow.banners

            NotificationBanner {
                id: banner

                width: slot.width
                ready: bannerWindow.presented
                appName: slot.model.appName
                appIcon: slot.model.appIcon
                desktopEntry: slot.model.desktopEntry
                title: slot.model.summary
                body: slot.model.body
                time: slot.model.time
                image: slot.model.image
                actions: slot.model.actions
                actionIcons: slot.model.actionIcons
                files: slot.model.files
                hasDefaultAction: slot.model.hasDefaultAction
                inlineReply: slot.model.inlineReply
                replyPlaceholder: slot.model.replyPlaceholder
                replySubmitText: slot.model.replySubmitText
                urgency: slot.model.urgency
                originName: slot.model.originName
                waiting: popups.waiting

                onLeaveFinished: slot.ListView.delayRemove = false
                onSwipedAway: popups.hide(slot.model.notificationId)
                onDismissed: NotificationCenter.dismiss(slot.model.notificationId)
                onDefaultInvoked: NotificationCenter.invokeAction(slot.model.notificationId, "default", bannerWindow)
                onActionInvoked: key => NotificationCenter.invokeAction(slot.model.notificationId, key, bannerWindow)
                // Not hidden here: the answer leaves a moment later (with its activation token) and
                // a transient notification would be gone by then. The service closes it
                onReplied: text => NotificationCenter.reply(slot.model.notificationId, text, bannerWindow)
                // A file opened: this banner has done its job
                onFileOpened: url => {
                    bannerWindow.open(url)
                    popups.hide(slot.model.notificationId)
                }
            }

            // Where the banner rests: the mask does not follow its movement
            Maia.MaskArea {
                width: banner.width
                height: banner.height
                visible: !banner.leaving
            }
        }
    }
}
