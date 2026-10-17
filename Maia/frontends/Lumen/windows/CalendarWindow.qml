import QtQuick
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell

import ".."
import "../components"

// Notification center and calendar, in the bottom-right corner above the clock.
// The notifications are mock data (Shell.notifications), the calendar is real.
FlyoutWindow {
    id: calendarFlyout

    flyoutName: "calendar"
    cardWidth: 380
    // The card follows its content (number of notifications), the window keeps the largest size
    windowCardHeight: Math.min(820, Screen.height - Theme.taskbarHeight - 2 * shadowMargin - Theme.spacingS)
    cardHeight: Math.min(windowCardHeight, layout.implicitHeight + 2 * Theme.spacingL)

    // Height of everything except the notification list, the list gets the rest of the card
    readonly property int fixedContentHeight: notificationsHeader.implicitHeight + 1 + dateLabel.implicitHeight
                                              + calendarView.implicitHeight + focusCard.Layout.preferredHeight
                                              + 5 * layout.spacing + 2 * Theme.spacingL
    edges: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

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
                visible: Shell.notifications.count > 0
                leftPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                onClicked: Shell.notifications.clear()
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
            model: Shell.notifications
            boundsBehavior: Flickable.StopAtBounds

            delegate: NotificationCard {
                required property int index
                required property string app
                required property string icon
                // Existing properties of NotificationCard filled from the roles of the same name
                required title
                required body
                required time

                width: notificationList.width
                appName: app
                iconName: icon
                onDismissed: Shell.notifications.remove(index)
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

                Behavior on opacity { NumberAnimation { duration: Theme.durationSlow } }

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

        // --- Focus session (mock) ---

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
                    LText { text: qsTr("30 minutes, no notifications"); font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
                }

                AccentButton {
                    text: Shell.focusMode ? qsTr("Stop") : qsTr("Start")
                    onClicked: Shell.focusMode = !Shell.focusMode
                }
            }
        }
    }
}
