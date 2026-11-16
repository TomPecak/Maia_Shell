import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia
import Maia.Notifications.Center
import Maia.Sounds
import Maia.Windows as Windows

import LumenFrontend

// Notification popups in the bottom-right corner, above the taskbar (as on Windows 11): the newest
// at the bottom, at most three, the rest waits for a place.
//
// What pops up and for how long is Maia.Notifications.Center's (NotificationPopupsModel counts the time);
// this window only shows it. The clocks stop while the pointer is over the popups or an answer is
// being typed. Only the cards take input (MaskArea), the rest of the window lets clicks through.
// While the user works fullscreen on this screen (a film, a game) only critical notifications pop
// up, the others go into the notification center; nothing comes back afterwards. So the window can
// sit in the overlay layer, above fullscreen windows, where a critical warning must be seen.
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
    // A file is being dragged out of a popup: the popups wait (a drag outlives the hover)
    property bool dragging: false
    // Jobs the user hid from the popups (they go on in the notification center)
    property var hiddenJobs: ({})
    // Jobs that ended while shown: a few seconds more ("Done", "Open folder")
    property var endedJobs: ({})
    readonly property int endedJobTime: 6000
    // Jobs shown as popups: running or just ended, not hidden, not while fullscreen
    readonly property int shownJobs: {
        if (fullscreen.active)
            return 0
        let shown = 0
        for (let row = 0; row < jobs.count; ++row) {
            const index = jobs.index(row, 0)
            const id = jobs.data(index, JobsModel.JobIdRole)
            const running = jobs.data(index, JobsModel.StateRole) < 2
            if (!hiddenJobs[id] && (running || endedJobs[id]))
                ++shown
        }
        return shown
    }

    function setJobFlag(name, id, on) {
        const flags = Object.assign({}, popupsWindow[name])
        if (on)
            flags[id] = true
        else
            delete flags[id]
        popupsWindow[name] = flags
    }
    onShownJobsChanged: updateShown()

    width: cardWidth + 2 * margin
    height: Math.min(Screen.height - Theme.taskbarHeight, 720)
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: shown

    LayerShell.Window.scope: "lumen-notifications"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: 0
    // The keyboard only for an answer
    LayerShell.Window.keyboardInteractivity: replying ? LayerShell.Window.KeyboardInteractivityOnDemand
                                                      : LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false

    // The window the user works in is fullscreen on this screen
    Windows.FullscreenState {
        id: fullscreen

        screen: popupsWindow.screen
    }

    NotificationPopupsModel {
        id: popups

        suppressed: fullscreen.active

        // The sound the sender asked for, when its popup appears (a sender that plays its own, as
        // every KDE application through KNotification, asks for none or suppresses it)
        onPopupShown: (notificationId, soundName, soundFile, suppressSound) => {
            if (!suppressSound)
                Sounds.play(soundName, soundFile)
        }
        maximumCount: 3
        paused: listHover.hovered || jobsHover.hovered || popupsWindow.replying || popupsWindow.dragging

        onCountChanged: popupsWindow.updateShown()
    }

    Component.onCompleted: updateShown()

    // The copies and other jobs, shown above the notifications while they run and a moment after
    JobsModel {
        id: jobs
    }

    function updateShown() {
        if (popups.count > 0 || shownJobs > 0) {
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

    Column {
        id: jobPopups

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: list.top
        anchors.leftMargin: popupsWindow.margin
        anchors.rightMargin: popupsWindow.margin
        anchors.bottomMargin: list.count > 0 ? Theme.spacingS : 0
        spacing: Theme.spacingS
        visible: popupsWindow.shownJobs > 0

        HoverHandler {
            id: jobsHover
        }

        Repeater {
            model: jobs

            delegate: JobCard {
                id: jobCard

                required property var model

                width: jobPopups.width
                visible: !popupsWindow.hiddenJobs[model.jobId] && (running || !!popupsWindow.endedJobs[model.jobId])
                hideable: true
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1)
                appName: model.appName
                iconName: model.appIcon
                desktopEntry: model.desktopEntry
                title: model.title
                infoMessage: model.infoMessage
                state: model.state
                percent: model.percent
                processedBytes: model.processedBytes
                totalBytes: model.totalBytes
                processedFiles: model.processedFiles
                totalFiles: model.totalFiles
                speed: model.speed
                destination: model.destination
                errorText: model.errorText
                ownerGone: model.ownerGone
                killable: model.killable
                suspendable: model.suspendable

                onPauseRequested: paused => NotificationCenter.suspendJob(model.jobId, paused)
                onCancelRequested: NotificationCenter.cancelJob(model.jobId)
                onDismissed: popupsWindow.setJobFlag("hiddenJobs", model.jobId, true)

                // Ended while on screen: shown a moment longer (a job that ended before the shell
                // came is in the notification center only)
                onRunningChanged: {
                    if (!running) {
                        popupsWindow.setJobFlag("endedJobs", model.jobId, true)
                        endTimer.restart()
                    }
                }

                Timer {
                    id: endTimer

                    interval: popupsWindow.endedJobTime
                    onTriggered: popupsWindow.setJobFlag("endedJobs", jobCard.model.jobId, false)
                }

                Maia.MaskArea {
                    anchors.fill: parent
                    enabled: parent.visible
                }
            }
        }
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
            actionIcons: model.actionIcons
            files: model.files
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
            onDraggingChanged: popupsWindow.dragging = dragging
            // A file opened: this popup has done its job
            onFileOpened: popups.hide(model.notificationId)

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
