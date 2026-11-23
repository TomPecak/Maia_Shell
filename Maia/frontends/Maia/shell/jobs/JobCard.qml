pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

import "../notifications"
import "JobFormat.js" as JobFormat

// A job in full (a copy in Dolphin, an archive): what it does, how far it is, how fast and how long
// still, with pause and cancel; when it has ended, how it went, "Open Folder" and a cross. In the
// notification center and in the expanded pill. `job` is a row of JobsModel or JobPopupsModel; this
// card only shows it and says what was asked.
//
// Cancelling loses the work done, so it asks once more, on the same button: nothing moves under the
// finger and the question goes away by itself.
//
// Performance: the numbers that change all the time (bytes, speed, time left) are read once a second
// while the card is seen. They stay readable, and there is no text layout four times a second.
Rectangle {
    id: card

    required property var job

    readonly property int jobState: info().state
    readonly property bool running: jobState === 0 || jobState === 1
    readonly property bool paused: jobState === 1
    readonly property bool failed: jobState === 3
    readonly property bool canPause: running && info().suspendable
    readonly property bool canCancel: running && info().killable
    readonly property bool hasFolder: !running && !failed && info().destination.length > 0
    // The cross of an ended job
    property bool closable: true
    // "Cancel" asks for confirmation now
    property bool cancelArmed: false
    property string detail

    signal pauseRequested(bool paused)
    signal cancelRequested()
    signal dismissed()
    signal openFolderRequested(string url)

    // Never null. A function and not a property: when a row goes, its object dies a moment before the
    // card, and a property holding it would not be told
    function info() {
        return job ?? JobFormat.emptyJob
    }

    function readDetail() {
        detail = running ? JobFormat.progress(info()) : JobFormat.ended(info())
    }

    implicitHeight: content.implicitHeight + 2 * content.y
    radius: 22
    color: Theme.plate
    border.width: failed ? 2 : 1
    border.color: failed ? Theme.red : Theme.hairline

    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: Theme.label

    Accessible.role: Accessible.ProgressBar
    Accessible.name: JobFormat.title(info())
    Accessible.description: detail

    onJobStateChanged: {
        cancelArmed = false
        // After every role of this update has arrived
        Qt.callLater(readDetail)
    }
    onVisibleChanged: {
        if (visible)
            readDetail()
    }
    Component.onCompleted: readDetail()

    Timer {
        interval: 1000
        repeat: true
        running: card.visible && card.running
        onTriggered: card.readDetail()
    }

    Timer {
        id: disarm

        interval: 3000
        onTriggered: card.cancelArmed = false
    }

    Column {
        id: content

        x: 14
        y: 14
        width: card.width - 2 * x
        spacing: 10

        Item {
            width: content.width
            height: Math.max(38, texts.implicitHeight)

            Kirigami.Icon {
                id: icon

                width: 38
                height: 38
                roundToIconSize: false
                source: card.info().appIcon.length > 0 ? card.info().appIcon
                      : card.info().desktopEntry.length > 0 ? card.info().desktopEntry
                      : "system-run"
                fallback: "application-x-executable"
            }

            Column {
                id: texts

                anchors.left: icon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                spacing: 1

                Text {
                    objectName: "jobMeta"
                    width: parent.width - (closeButton.visible ? closeButton.width : percentText.implicitWidth + 4)
                    text: card.info().appName
                    elide: Text.ElideRight
                    color: Theme.secondaryLabel
                    font.pixelSize: 12
                }

                Text {
                    objectName: "jobTitle"
                    width: parent.width
                    text: JobFormat.title(card.info())
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.label
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    objectName: "jobInfo"
                    width: parent.width
                    visible: card.running && card.info().infoMessage.length > 0 && card.info().infoMessage !== card.info().title
                    text: card.info().infoMessage
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: Theme.secondaryLabel
                    font.pixelSize: 13
                }
            }

            Text {
                id: percentText

                objectName: "jobPercent"
                anchors.right: parent.right
                visible: card.running && card.info().percent >= 0
                text: qsTr("%1 %").arg(card.info().percent)
                color: Theme.secondaryLabel
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            NotificationButton {
                id: closeButton

                objectName: "jobCloseButton"
                anchors.right: parent.right
                anchors.rightMargin: -11
                anchors.top: parent.top
                anchors.topMargin: -13
                visible: !card.running && card.closable
                round: true
                glyph: Qt.resolvedUrl("../../assets/icons/window-close-symbolic.svg")
                text: qsTr("Dismiss")
                onClicked: card.dismissed()
            }
        }

        JobBar {
            objectName: "jobBar"
            width: content.width
            visible: card.running
            percent: card.info().percent
            moving: !card.paused
            tint: card.paused ? Theme.secondaryLabel : Theme.accent
        }

        Text {
            objectName: "jobDetail"
            width: content.width
            visible: text.length > 0
            text: card.detail
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: card.failed ? Theme.red : Theme.secondaryLabel
            font.pixelSize: 13
            font.features: { "tnum": 1 }
        }

        Row {
            id: actions

            // From what the card can do, not from the buttons' visible: that is false while the
            // card itself is unseen, and the row would never come back
            readonly property int shown: (card.canPause ? 1 : 0) + (card.canCancel ? 1 : 0) + (card.hasFolder ? 1 : 0)
            readonly property real buttonWidth: (content.width - (shown - 1) * spacing) / Math.max(1, shown)

            visible: shown > 0
            spacing: 8

            NotificationButton {
                id: pauseButton

                objectName: "jobPauseButton"
                width: actions.buttonWidth
                visible: card.canPause
                text: card.paused ? qsTr("Resume") : qsTr("Pause")
                onClicked: card.pauseRequested(!card.paused)
            }

            NotificationButton {
                id: cancelButton

                objectName: "jobCancelButton"
                width: actions.buttonWidth
                visible: card.canCancel
                text: card.cancelArmed ? qsTr("Really cancel?") : qsTr("Cancel")
                prominent: card.cancelArmed
                prominentColor: Theme.red
                onClicked: {
                    if (card.cancelArmed) {
                        disarm.stop()
                        card.cancelArmed = false
                        card.cancelRequested()
                    } else {
                        card.cancelArmed = true
                        disarm.restart()
                    }
                }
            }

            NotificationButton {
                id: folderButton

                objectName: "jobFolderButton"
                width: actions.buttonWidth
                visible: card.hasFolder
                text: qsTr("Open Folder")
                onClicked: card.openFolderRequested(JobFormat.folderUrl(card.info().destination))
            }
        }
    }
}
