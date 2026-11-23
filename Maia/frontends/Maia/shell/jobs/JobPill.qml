pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import MaiaFrontend

import "JobFormat.js" as JobFormat

// A running job as a small pill at the top of the screen (a Live Activity of iPadOS): a ring, what it
// does and how far it is. A tap unfolds it into the whole card (pause, cancel, details), a swipe up
// puts it away: the job goes on, in the notification center and in the ring by the clock.
//
// Only shows data and says what was asked: JobPillWindow.qml talks to the notification center.
//
// Performance: it comes, goes and steps aside on the render thread; the root item never moves, so
// the input mask does not follow it. Between two whole percents nothing in it changes, so a long copy
// renders a frame now and then, not sixty a second. The card is created ahead, between frames.
Item {
    id: pill

    required property var job
    // Running jobs without a place of their own
    property int others: 0
    // The window has its first frame (no frame of the way in is lost)
    property bool ready: true
    // A notification banner is on screen: one thing at a time at the top
    property bool covered: false

    readonly property bool expanded: d.expanded
    readonly property bool leaving: d.leaving
    // The user is busy with it: an ended job waits
    readonly property bool held: hover.hovered || tap.pressed || swipe.active || d.expanded
    // Where it takes input
    readonly property real restingWidth: d.targetWidth
    readonly property real restingHeight: d.targetHeight

    signal swipedAway()
    signal pauseRequested(bool paused)
    signal cancelRequested()
    signal dismissed()
    signal openFolderRequested(string url)
    // "2 more": the list of them
    signal moreRequested()
    // The way out has ended (leave())
    signal leaveFinished()

    function leave(replaced) {
        if (d.leaving)
            return
        d.leaving = true
        enter.stop()
        snapBack.stop()
        if (!d.entered) {
            pill.leaveFinished()
            return
        }
        if (replaced)
            sink.start()
        else
            rise.start()
    }

    // Never null: when a row goes, its object dies a moment before the pill (JobCard.qml)
    function info() {
        return job ?? JobFormat.emptyJob
    }

    function setExpanded(value) {
        d.expanded = value
    }

    height: d.targetHeight

    onReadyChanged: d.comeIn()
    Component.onCompleted: d.comeIn()

    Accessible.role: Accessible.ProgressBar
    Accessible.name: JobFormat.title(pill.info())
    Accessible.description: JobFormat.shortState(pill.info())

    QtObject {
        id: d

        property bool leaving: false
        property bool entered: false
        property bool expanded: false
        readonly property int compactHeight: 52
        readonly property int compactWidth: Math.min(pill.width, compact.implicitWidth + 2 * 11)
        readonly property int targetWidth: expanded ? pill.width : compactWidth
        readonly property int targetHeight: expanded && cardLoader.item
                                            ? cardLoader.item.implicitHeight + (pill.others > 0 ? 44 : 0)
                                            : compactHeight
        readonly property int offScreen: mover.height + 24
        readonly property int swipeAway: 24

        function comeIn() {
            if (!pill.ready || entered || leaving)
                return
            entered = true
            enter.start()
        }

        function pulled(distance) {
            return distance < 0 ? distance : Math.min(distance * 0.3, 24)
        }

        function released(velocity) {
            const distance = mover.y
            if (distance < -swipeAway || (velocity < -400 && distance < -8)) {
                pill.swipedAway()
                return
            }
            if (distance > 16 && !expanded)
                expanded = true
            snapBack.start()
        }
    }

    // Steps aside for a banner, whatever the pill is doing
    Item {
        anchors.fill: parent
        opacity: pill.covered ? 0 : 1
        enabled: !pill.covered

        Behavior on opacity {
            OpacityAnimator { duration: 180; easing.type: Easing.OutQuad }
        }

        Item {
            id: mover

            x: (pill.width - width) / 2
            width: d.targetWidth
            height: d.targetHeight
            opacity: 0
            scale: tap.pressed && !swipe.active ? 0.97 : 1

            Behavior on width {
                enabled: d.entered && !d.leaving

                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                enabled: d.entered && !d.leaving

                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
            }

            RectangularShadow {
                anchors.fill: plate
                offset.y: 5
                blur: 20
                radius: plate.radius
                color: Theme.shadow
            }

            Rectangle {
                id: plate

                objectName: "jobPillPlate"
                anchors.fill: parent
                radius: d.expanded ? 22 : 26
                color: Theme.card
                border.width: pill.info().state === 3 ? 2 : 1
                border.color: pill.info().state === 3 ? Theme.red : Theme.hairline
                clip: true

                HoverHandler {
                    id: hover
                }

                TapHandler {
                    id: tap

                    enabled: !pill.leaving
                    cursorShape: Qt.PointingHandCursor
                    onTapped: d.expanded = !d.expanded
                }

                DragHandler {
                    id: swipe

                    target: null
                    xAxis.enabled: false
                    enabled: !pill.leaving
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

                // --- Compact ---

                Row {
                    id: compact

                    objectName: "jobPillCompact"
                    x: 11
                    y: (d.compactHeight - height) / 2
                    spacing: 10
                    opacity: d.expanded ? 0 : 1
                    visible: opacity > 0 || !d.expanded

                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                    }

                    JobRing {
                        objectName: "jobPillRing"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        percent: pill.info().percent
                        jobState: pill.info().state
                    }

                    Text {
                        objectName: "jobPillTitle"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 210)
                        text: JobFormat.title(pill.info())
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.label
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    // As wide as "100 %" while it counts: the pill must not change size at 10 %
                    TextMetrics {
                        id: widestPercent

                        font: stateText.font
                        text: qsTr("%1 %").arg(100)
                    }

                    Text {
                        id: stateText

                        objectName: "jobPillState"
                        anchors.verticalCenter: parent.verticalCenter
                        width: pill.info().state === 0 ? Math.max(implicitWidth, Math.ceil(widestPercent.width)) : implicitWidth
                        horizontalAlignment: Text.AlignRight
                        visible: text.length > 0
                        text: JobFormat.shortState(pill.info())
                        color: pill.info().state === 3 ? Theme.red : Theme.secondaryLabel
                        font.pixelSize: 14
                        font.features: { "tnum": 1 }
                    }

                    Rectangle {
                        objectName: "jobPillMore"
                        anchors.verticalCenter: parent.verticalCenter
                        width: moreText.implicitWidth + 12
                        height: 22
                        radius: 11
                        visible: pill.others > 0
                        color: Theme.fill

                        Text {
                            id: moreText

                            anchors.centerIn: parent
                            text: "+" + pill.others
                            color: Theme.secondaryLabel
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // --- Unfolded ---

                Loader {
                    id: cardLoader

                    width: pill.width
                    x: (plate.width - width) / 2
                    asynchronous: true
                    opacity: d.expanded ? 1 : 0
                    visible: status === Loader.Ready && (d.expanded || plate.height > d.compactHeight + 1)

                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
                    }

                    sourceComponent: JobCard {
                        job: pill.job
                        color: "transparent"
                        border.width: 0
                        closable: true
                        onPauseRequested: paused => pill.pauseRequested(paused)
                        onCancelRequested: pill.cancelRequested()
                        onDismissed: pill.dismissed()
                        onOpenFolderRequested: url => pill.openFolderRequested(url)
                    }
                }

                MouseArea {
                    objectName: "jobPillMoreButton"
                    y: cardLoader.item ? cardLoader.item.implicitHeight - 6 : 0
                    width: plate.width
                    height: 44
                    visible: d.expanded && pill.others > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.moreRequested()

                    Accessible.role: Accessible.Button
                    Accessible.name: moreLabel.text
                    Accessible.onPressAction: pill.moreRequested()

                    Text {
                        id: moreLabel

                        anchors.centerIn: parent
                        text: qsTr("%n more running", "", pill.others)
                        color: Theme.accent
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // --- Movement, on the render thread ---

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
            script: pill.leaveFinished()
        }
    }

    SequentialAnimation {
        id: sink

        ParallelAnimation {
            ScaleAnimator {
                target: mover
                to: 0.9
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
            script: pill.leaveFinished()
        }
    }
}
