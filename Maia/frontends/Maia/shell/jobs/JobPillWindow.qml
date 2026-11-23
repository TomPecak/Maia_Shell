pragma ComponentBehavior: Bound

import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia
import Maia.Notifications.Center
import Maia.Windows as Windows

import MaiaFrontend

import "../notifications"

// The job in progress as a pill at the top of the screen, in the same place as the banners. Which job
// and for how long is Maia.Notifications.Center's (JobPopupsModel); this window only shows it.
//
// A window of its own and small, because it can stay for a long copy, while the banners' is mapped
// for seconds: the compositor has little to blend, and it is not shown at all over a fullscreen
// window, which can then be scanned out directly. Nor while the Control Center, the App Library or
// the notification center are open: the screen is theirs, and the last shows the job anyway. It steps
// aside while a banner is on screen. It never takes the keyboard.
Window {
    id: pillWindow

    // A banner is on screen
    property bool covered: false

    readonly property int contentWidth: Math.min(420, Screen.width - 32)
    // The pill that is not on its way out
    property JobPill current: null
    // Pills in the window, those on their way out too
    property int pills: 0
    // The first frame is on screen, so the pill's way in loses none of its movement
    property bool presented: false

    width: Math.min(Screen.width, contentWidth + 2 * place.shadowMargin + place.dockRoom)
    height: Math.min(Screen.height, 340 + place.dockRoom)
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: live.count > 0 || pills > 0

    LayerShell.Window.scope: "maia-job-pill"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
    LayerShell.Window.activateOnShow: false

    onVisibleChanged: presented = false

    // Emitted on the render thread, delivered to QML on this one; listened to only until it comes
    Connections {
        target: pillWindow
        enabled: pillWindow.visible && !pillWindow.presented

        function onFrameSwapped() {
            pillWindow.presented = true
        }
    }

    Windows.FullscreenState {
        id: fullscreen

        screen: pillWindow.screen
    }

    JobPopupsModel {
        id: live

        maximumCount: 1
        suppressed: fullscreen.active || ShellState.modalOpen
        paused: pillWindow.current !== null && pillWindow.current.held
    }

    TopCenterPlace {
        id: place

        host: pillWindow
        contentWidth: pillWindow.contentWidth
        presented: pillWindow.presented
        dockVisible: !fullscreen.active

        ListView {
            id: list

            anchors.fill: parent
            interactive: false
            model: live

            // No height of its own: a pill on its way out and the one taking its place lie in the
            // same spot (see BannerWindow.qml)
            delegate: Item {
                id: slot

                required property var model

                width: list.width
                height: 0

                ListView.onRemove: {
                    slot.ListView.delayRemove = true
                    if (pillWindow.current === pill)
                        pillWindow.current = null
                    pill.leave(live.count > 0)
                }

                Component.onCompleted: {
                    ++pillWindow.pills
                    pillWindow.current = pill
                }
                Component.onDestruction: --pillWindow.pills

                JobPill {
                    id: pill

                    width: slot.width
                    job: slot.model
                    others: live.waiting
                    ready: pillWindow.presented
                    covered: pillWindow.covered

                    onLeaveFinished: slot.ListView.delayRemove = false
                    onSwipedAway: live.hide(slot.model.jobId)
                    onPauseRequested: paused => NotificationCenter.suspendJob(slot.model.jobId, paused)
                    onCancelRequested: NotificationCenter.cancelJob(slot.model.jobId)
                    onDismissed: NotificationCenter.dismissJob(slot.model.jobId)
                    onOpenFolderRequested: url => {
                        if (typeof backend !== "undefined" && backend)
                            backend.runCommand("xdg-open " + url)
                        live.hide(slot.model.jobId)
                    }
                    onMoreRequested: ShellState.notificationCenterRequested()
                }

                // Where the pill rests: the mask does not follow its movement
                Maia.MaskArea {
                    x: (pill.width - width) / 2
                    width: pill.restingWidth
                    height: pill.restingHeight
                    visible: !pill.leaving && !pill.covered
                }
            }
        }
    }
}
