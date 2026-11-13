import QtQuick
import QtQuick.Layouts

import LumenFrontend

// A job of an application (a copy in Dolphin, an archive): what it does, how far it is, how fast,
// how long still, and pause / cancel; when it has ended, "Open folder" and a close button. The
// data comes from Maia.Notifications.Center (JobsModel), this card only shows it.
Card {
    id: card

    property string appName
    property string iconName
    property string desktopEntry
    property string title
    property string infoMessage
    // NotificationCenter.JobState: 0 running, 1 paused, 2 finished, 3 failed
    property int state: 0
    // 0 .. 100, -1 unknown
    property int percent: -1
    property real processedBytes: 0
    property real totalBytes: 0
    property real processedFiles: 0
    property real totalFiles: 0
    // bytes per second
    property real speed: 0
    property string destination
    property string errorText
    property bool ownerGone: false
    property bool killable: false
    property bool suspendable: false

    // A close button also while it runs (a popup: hidden, the job goes on in the center)
    property bool hideable: false

    readonly property bool running: state === 0 || state === 1
    readonly property bool paused: state === 1
    readonly property bool failed: state === 3

    signal pauseRequested(bool paused)
    signal cancelRequested()
    signal dismissed()

    implicitHeight: content.implicitHeight + 2 * Theme.spacingM
    border.color: card.failed ? Theme.critical : Theme.stroke

    function size(bytes) {
        return Qt.locale().formattedDataSize(bytes)
    }

    // "400 MB of 1 GB · 25 MB/s · 20 s left", or what is known of it
    readonly property string progressText: {
        const parts = []
        if (totalBytes > 0)
            parts.push(qsTr("%1 of %2").arg(card.size(processedBytes)).arg(card.size(totalBytes)))
        else if (totalFiles > 1)
            parts.push(qsTr("%1 of %2 files").arg(processedFiles).arg(totalFiles))
        if (paused) {
            parts.push(qsTr("Paused"))
        } else if (speed > 0) {
            parts.push(qsTr("%1/s").arg(card.size(speed)))
            if (totalBytes > processedBytes) {
                const seconds = Math.round((totalBytes - processedBytes) / speed)
                parts.push(seconds < 60 ? qsTr("%1 s left").arg(Math.max(1, seconds))
                                        : seconds < 3600 ? qsTr("%1 min left").arg(Math.round(seconds / 60))
                                                         : qsTr("%1 h %2 min left").arg(Math.floor(seconds / 3600)).arg(Math.round((seconds % 3600) / 60)))
            }
        }
        return parts.join(" · ")
    }

    readonly property string endText: failed ? (ownerGone ? qsTr("%1 closed before it was done.").arg(appName || qsTr("The application"))
                                                          : (errorText.length > 0 ? errorText : qsTr("It did not succeed.")))
                                             : totalBytes > 0 ? qsTr("Done, %1").arg(card.size(totalBytes))
                                             : totalFiles > 1 ? qsTr("Done, %1 files").arg(totalFiles) : qsTr("Done")

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingXS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            LIcon {
                size: 16
                iconName: card.iconName.length > 0 ? card.iconName : card.desktopEntry
                tinted: iconName.endsWith("-symbolic")
            }

            LText {
                Layout.fillWidth: true
                text: card.appName
                elide: Text.ElideRight
                font.pixelSize: Theme.fontCaption
                color: Theme.textSecondary
            }

            SubtleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                padding: 0
                visible: (card.hideable || !card.running) && hover.hovered
                Accessible.name: card.running ? qsTr("Hide") : qsTr("Dismiss")
                contentItem: Item { LIcon { anchors.centerIn: parent; size: 12; iconName: "window-close-symbolic" } }
                onClicked: card.dismissed()
            }
        }

        LText {
            Layout.fillWidth: true
            text: card.title.length > 0 ? card.title : qsTr("Working")
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        LText {
            Layout.fillWidth: true
            visible: card.running && card.infoMessage.length > 0 && card.infoMessage !== card.title
            text: card.infoMessage
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideMiddle
        }

        // The bar: its share, or a moving piece when the share is unknown
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXS
            visible: card.running
            implicitHeight: 4
            radius: 2
            color: Theme.controlStrong
            clip: true

            Rectangle {
                visible: card.percent >= 0
                width: parent.width * Math.max(0, Math.min(100, card.percent)) / 100
                height: parent.height
                radius: 2
                color: card.paused ? Theme.textTertiary : Theme.accent

                Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }
            }

            Rectangle {
                id: unknown

                visible: card.percent < 0 && !card.paused
                width: parent.width / 4
                height: parent.height
                radius: 2
                color: Theme.accent

                XAnimator on x {
                    running: unknown.visible
                    from: -unknown.width
                    to: unknown.parent.width
                    duration: 1200
                    loops: Animation.Infinite
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            LText {
                Layout.fillWidth: true
                text: card.running ? card.progressText : card.endText
                color: card.failed ? Theme.critical : Theme.textSecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            LText {
                visible: card.running && card.percent >= 0
                text: qsTr("%1 %").arg(card.percent)
                font.pixelSize: Theme.fontCaption
                font.features: { "tnum": 1 }
            }
        }

        // --- Actions ---

        Row {
            Layout.topMargin: Theme.spacingXS
            spacing: Theme.spacingS
            visible: card.running ? (card.suspendable || card.killable) : (!card.failed && card.destination.length > 0)

            component Action: SubtleButton {
                id: action

                property string label

                leftPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                Accessible.name: label
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: action.pressed ? Theme.subtlePressed : action.hovered ? Theme.subtleHover : Theme.control
                    border.width: 1
                    border.color: Theme.stroke
                }
                contentItem: LText { text: action.label; font.pixelSize: Theme.fontCaption }
            }

            Action {
                visible: card.running && card.suspendable
                label: card.paused ? qsTr("Resume") : qsTr("Pause")
                onClicked: card.pauseRequested(!card.paused)
            }

            Action {
                visible: card.running && card.killable
                label: qsTr("Cancel")
                onClicked: card.cancelRequested()
            }

            Action {
                visible: !card.running && !card.failed && card.destination.length > 0
                label: qsTr("Open folder")
                // Through the shell: a program it starts gets a clean environment (Backend.runCommand)
                onClicked: Shell.launch("xdg-open " + (card.destination.indexOf("%") >= 0 ? card.destination : encodeURI(card.destination)))
            }
        }
    }
}
