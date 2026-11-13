import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia
import Maia.Notifications.Center

import LumenFrontend

// Notification popups in the bottom-right corner, above the taskbar (as on Windows 11): the newest
// at the bottom, at most three, the rest waits for a place.
//
// What pops up and for how long is Maia.Notifications.Center's (NotificationPopupsModel counts the time);
// this window only shows it. The clocks stop while the pointer is over the popups or an answer is
// being typed. Only the cards take input (MaskArea), the rest of the window lets clicks through.
// The window never takes the keyboard by itself (a popup must not take it from the program being
// typed in), only while an answer field is open.
// Popups slide in and out (view transitions: Animators would leave an added popup invisible).
Window {
    id: popupsWindow

    readonly property int cardWidth: 360
    readonly property int margin: Theme.spacingM
    // Shown while there are popups, and a moment longer for the last one to slide out
    property bool shown: false
    // An answer field of a popup is open
    property bool replying: false

    width: cardWidth + 2 * margin
    height: Math.min(Screen.height - Theme.taskbarHeight, 720)
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: shown

    LayerShell.Window.scope: "lumen-notifications"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: 0
    // The keyboard only for an answer
    LayerShell.Window.keyboardInteractivity: replying ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                      : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false

    NotificationPopupsModel {
        id: popups

        maximumCount: 3
        paused: listHover.hovered || popupsWindow.replying

        onCountChanged: popupsWindow.updateShown()
    }

    Component.onCompleted: updateShown()

    function updateShown() {
        if (popups.count > 0) {
            hideTimer.stop()
            shown = true
        } else {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer

        interval: Theme.durationNormal + 100
        onTriggered: popupsWindow.shown = false
    }

    ListView {
        id: list

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: popupsWindow.margin
        height: Math.min(contentHeight, popupsWindow.height - 2 * popupsWindow.margin)
        interactive: false
        spacing: Theme.spacingS
        model: popups

        HoverHandler {
            id: listHover
        }

        delegate: NotificationCard {
            id: card

            required property int index
            required property var model

            width: list.width
            appName: model.appName
            iconName: model.appIcon
            desktopEntry: model.desktopEntry
            title: model.summary
            body: model.body
            time: model.time
            image: model.image
            actions: model.actions
            hasDefaultAction: model.hasDefaultAction
            inlineReply: model.inlineReply
            replyPlaceholder: model.replyPlaceholder
            replySubmitText: model.replySubmitText
            urgency: model.urgency
            originName: model.originName
            maximumLineCount: 2
            // Opaque: whatever is below (a window, the timer) must not show through
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1)

            onReplyingChanged: popupsWindow.replying = replying

            onDismissed: NotificationCenter.dismiss(model.notificationId)
            onDefaultInvoked: NotificationCenter.invokeAction(model.notificationId, "default", popupsWindow)
            onActionInvoked: key => NotificationCenter.invokeAction(model.notificationId, key, popupsWindow)
            onReplied: text => NotificationCenter.reply(model.notificationId, text, popupsWindow)

            Maia.MaskArea {
                anchors.fill: parent
            }
        }

        // A new popup slides in from the right edge, a finished one fades out to the right
        add: Transition {
            NumberAnimation { property: "x"; from: popupsWindow.cardWidth / 2; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
        }
        remove: Transition {
            NumberAnimation { property: "x"; to: popupsWindow.cardWidth / 2; duration: Theme.durationNormal; easing.type: Theme.easingExit }
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingExit }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.durationNormal; easing.type: Theme.easingStandard }
        }
    }
}
