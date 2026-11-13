import QtQuick
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell

import Maia.Notifications.Center

import LumenFrontend

// Notification center and calendar, in the bottom-right corner above the clock.
// The notifications are those of the session (Maia.Notifications.Center), the newest first.
FlyoutWindow {
    id: calendarFlyout

    flyoutName: "calendar"
    cardWidth: 380
    // The card follows its content (number of notifications), the window keeps the largest size
    windowCardHeight: Math.min(820, Screen.height - Theme.taskbarHeight - 2 * shadowMargin - Theme.spacingS)
    cardHeight: Math.min(windowCardHeight, layout.implicitHeight + 2 * Theme.spacingL)

    // Height of everything except the notification list, the list gets the rest of the card
    readonly property int fixedContentHeight: notificationsHeader.implicitHeight + 1 + dateLabel.implicitHeight
                                              + (jobsSection.visible ? jobsSection.implicitHeight + layout.spacing : 0)
                                              + calendarView.implicitHeight + focusCard.Layout.preferredHeight
                                              + 5 * layout.spacing + 2 * Theme.spacingL
    edges: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        // --- Jobs: copies, archives (the newest first; ended ones until dismissed) ---

        ColumnLayout {
            id: jobsSection

            Layout.fillWidth: true
            visible: jobs.count > 0
            spacing: Theme.spacingS

            Repeater {
                model: JobsModel {
                    id: jobs
                }

                delegate: JobCard {
                    required property var model

                    Layout.fillWidth: true
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
                    onDismissed: NotificationCenter.dismissJob(model.jobId)
                }
            }
        }

        // --- Notifications ---

        RowLayout {
            id: notificationsHeader

            Layout.fillWidth: true

            LText {
                Layout.fillWidth: true
                leftPadding: Theme.spacingXS
                text: qsTr("Notifications")
                font.pixelSize: Theme.fontBodyLarge
                font.weight: Font.DemiBold
            }

            SubtleButton {
                visible: notifications.count > 0 || jobs.count > jobs.runningCount
                leftPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                onClicked: {
                    NotificationCenter.dismissAll()
                    // Ended jobs too (running ones stay: they are not done)
                    for (let row = 0; row < jobs.count; ++row) {
                        const index = jobs.index(row, 0)
                        if (jobs.data(index, JobsModel.StateRole) >= 2)
                            NotificationCenter.dismissJob(jobs.data(index, JobsModel.JobIdRole))
                    }
                }
                contentItem: LText { text: qsTr("Clear all"); font.pixelSize: Theme.fontCaption }
            }
        }

        ListView {
            id: notificationList

            Layout.fillWidth: true
            // As many notifications as fit into the card, the rest scrolls
            Layout.preferredHeight: count > 0 ? Math.min(contentHeight, calendarFlyout.windowCardHeight - calendarFlyout.fixedContentHeight)
                                              : 120
            spacing: Theme.spacingS
            clip: true
            model: NotificationsModel {
                id: notifications
            }
            boundsBehavior: Flickable.StopAtBounds

            delegate: NotificationCard {
                required property int index
                required property var model

                width: notificationList.width
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

                onDismissed: NotificationCenter.dismiss(model.notificationId)
                onDefaultInvoked: {
                    NotificationCenter.invokeAction(model.notificationId, "default", calendarFlyout)
                    Shell.closeFlyouts()
                }
                onActionInvoked: key => {
                    NotificationCenter.invokeAction(model.notificationId, key, calendarFlyout)
                    Shell.closeFlyouts()
                }
                onReplied: text => NotificationCenter.reply(model.notificationId, text, calendarFlyout)
            }

            // Removed notifications slide out to the right, the rest moves up
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; to: notificationList.width; duration: Theme.durationNormal; easing.type: Theme.easingExit }
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationNormal }
                }
            }
            removeDisplaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.durationNormal; easing.type: Theme.easingStandard }
            }

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                visible: notificationList.count === 0
                opacity: visible ? 1 : 0

                Behavior on opacity { OpacityAnimator { duration: Theme.durationSlow } }

                LIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 32
                    iconName: "notification-inactive-symbolic"
                    tint: Theme.textTertiary
                }
                LText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("No new notifications")
                    color: Theme.textSecondary
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.divider
        }

        // --- Calendar ---

        LText {
            id: dateLabel

            Layout.fillWidth: true
            leftPadding: Theme.spacingXS
            text: {
                const date = Shell.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                return date.charAt(0).toUpperCase() + date.slice(1)
            }
            font.pixelSize: Theme.fontBodyLarge
            font.weight: Font.DemiBold
        }

        CalendarView {
            id: calendarView

            Layout.fillWidth: true
        }

        // --- Focus session: do not disturb for 30 minutes ---

        Card {
            id: focusCard

            Layout.fillWidth: true
            Layout.preferredHeight: 56

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingM

                LIcon {
                    size: 18
                    iconName: "chronometer-symbolic"
                    tint: Theme.accent
                }

                Column {
                    Layout.fillWidth: true
                    LText { text: qsTr("Focus"); font.weight: Font.DemiBold }
                    LText {
                        text: NotificationCenter.doNotDisturb
                              ? (!isNaN(NotificationCenter.doNotDisturbUntil.getTime()) ? qsTr("No notifications until %1").arg(Qt.formatTime(NotificationCenter.doNotDisturbUntil, Qt.locale().timeFormat(Locale.ShortFormat)))
                                                                             : qsTr("No notifications"))
                              : qsTr("30 minutes, no notifications")
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textSecondary
                    }
                }

                AccentButton {
                    text: NotificationCenter.doNotDisturb ? qsTr("Stop") : qsTr("Start")
                    onClicked: {
                        if (NotificationCenter.doNotDisturb)
                            NotificationCenter.doNotDisturb = false
                        else
                            NotificationCenter.setDoNotDisturbFor(30)
                    }
                }
            }
        }
    }
}
