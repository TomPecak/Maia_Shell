pragma ComponentBehavior: Bound

import QtQuick

import MaiaFrontend

import "SwipeRules.js" as SwipeRules

// One row of the notification center: a notification, or the stack of an application.
//
//   tap             a stack unfolds; else the default action (without one: expands)
//   long press      expands
//   swipe left      opens a red "Clear" beside the card, as on iPadOS: only a tap on it deletes
//   swipe far left  deletes at once; past that point the button says so before the finger lifts
//   swipe right     closes what is open; nothing else
//
// Deleting cannot be undone, so no quick or short movement does it (SwipeRules.js). While "Clear" is
// open a tap on the card closes it instead of doing what a tap does.
//
// An unfolded group has a header with its name, "Show less" and "Clear". `model` is a row of
// NotificationGroupsModel. Says what was asked: NotificationCenterSheet.qml does it.
Item {
    id: row

    required property var model
    // The moment "5 min ago" is counted from
    property date now: new Date()
    // Another row has its "Clear" open: a tap here only closes that one
    property bool anotherRevealed: false

    readonly property alias card: card
    readonly property bool stacked: model.groupHead && !model.groupExpanded && model.groupCount > 1
    readonly property bool hasHeader: model.groupHead && model.groupExpanded
    // "Clear" is open
    readonly property bool revealed: d.revealed

    signal groupToggled(string key)
    signal groupCleared(string key)
    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string key)
    signal replied(string text)
    signal fileOpened(string url)
    // The user turned to this row: another row's "Clear" should close
    signal attentionTaken()

    function closeReveal() {
        d.moveTo(SwipeRules.closed)
    }

    implicitHeight: mover.y + mover.height + (stacked ? d.stackDepth : 0) + d.gap
    height: implicitHeight

    Component.onCompleted: d.ready = true

    QtObject {
        id: d

        property bool ready: false
        property bool revealed: false
        // Where the card was when the finger came down
        property real dragStart: 0
        readonly property int gap: 10
        // How far the plates of a stack show below the card
        readonly property int stackDepth: 14
        readonly property int headerHeight: 44
        // Between the card and its button
        readonly property int buttonGap: 8

        // How far left the card is
        readonly property real offset: Math.max(0, -mover.x)
        // Where it rests with "Clear" open: a quarter of the row, and always room for the label
        readonly property int revealWidth: Math.max(112, Math.round(row.width / 4))
        // Past this point letting go deletes
        readonly property int commitWidth: Math.round(row.width * 0.7)
        readonly property bool armed: swipe.active && offset >= commitWidth
        // 0..1, softly: the label travels to the card when letting go would delete
        property real armProgress: armed ? 1 : 0

        Behavior on armProgress {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        // Left follows the finger; right has nothing there and resists
        function follow(translation) {
            const x = dragStart + translation
            mover.x = x > 0 ? Math.min(x * 0.25, 24) : Math.max(x, -row.width)
        }

        function moveTo(state) {
            settle.stop()
            flyOut.stop()
            restore.stop()
            revealed = state === SwipeRules.revealed
            if (state === SwipeRules.clear) {
                flyOutX.to = -(row.width + 24)
                flyOut.start()
                return
            }
            settle.to = revealed ? -revealWidth : 0
            settle.start()
        }

        function clear() {
            if (row.stacked)
                row.groupCleared(row.model.groupKey)
            else
                row.dismissed()
        }
    }

    // --- The header of an unfolded group ---

    Item {
        id: header

        width: row.width
        height: row.hasHeader ? d.headerHeight : 0
        visible: row.hasHeader

        Text {
            objectName: "groupName"
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.right: groupButtons.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.model.appName
            elide: Text.ElideRight
            color: Theme.label
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Row {
            id: groupButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            NotificationButton {
                objectName: "showLessButton"
                text: qsTr("Show Less")
                onClicked: row.groupToggled(row.model.groupKey)
            }

            NotificationButton {
                objectName: "clearGroupButton"
                round: true
                plateSize: 32
                glyph: Qt.resolvedUrl("../../assets/icons/window-close-symbolic.svg")
                text: qsTr("Clear %1").arg(row.model.appName)
                onClicked: row.groupCleared(row.model.groupKey)
            }
        }
    }

    // --- "Clear", beside the card; it grows with the swipe ---

    Rectangle {
        id: clearButton

        objectName: "clearSwipeButton"
        x: row.width - width
        y: mover.y
        width: Math.max(0, d.offset - d.buttonGap)
        height: mover.height
        radius: Math.min(card.radius, width / 2)
        visible: width > 0
        color: clearArea.pressed ? Theme.redHover : Theme.red
        opacity: Math.min(1, d.offset / 36)

        Accessible.role: Accessible.Button
        Accessible.name: clearLabel.text
        Accessible.ignored: !d.revealed
        Accessible.onPressAction: d.moveTo(SwipeRules.clear)

        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
        }

        Text {
            id: clearLabel

            objectName: "clearSwipeLabel"
            // In the middle of the button; next to the card once letting go would delete
            x: (clearButton.width - implicitWidth) / 2 * (1 - d.armProgress) + 18 * d.armProgress
            anchors.verticalCenter: parent.verticalCenter
            text: row.stacked ? qsTr("Clear All") : qsTr("Clear")
            opacity: Math.max(0, Math.min(1, (clearButton.width - implicitWidth - 8) / 20))
            color: "white"
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: clearArea

            anchors.fill: parent
            enabled: d.revealed && !swipe.active
            cursorShape: Qt.PointingHandCursor
            onClicked: d.moveTo(SwipeRules.clear)
        }
    }

    // --- The card, and the plates of a stack under it ---

    Item {
        id: mover

        y: header.height
        width: row.width
        height: card.targetHeight
        scale: tap.pressed && !swipe.active && !d.revealed ? 0.98 : 1

        Behavior on height {
            enabled: d.ready

            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
            objectName: "stackPlate"
            x: 20
            y: mover.height - height + d.stackDepth
            width: row.width - 40
            height: 40
            radius: 18
            visible: row.stacked && row.model.groupCount > 2
            color: Theme.plate
            opacity: 0.55
            border.width: 1
            border.color: Theme.hairline
        }

        Rectangle {
            objectName: "stackPlate"
            x: 10
            y: mover.height - height + d.stackDepth / 2
            width: row.width - 20
            height: 40
            radius: 20
            visible: row.stacked
            color: Theme.plate
            opacity: 0.8
            border.width: 1
            border.color: Theme.hairline
        }

        NotificationCard {
            id: card

            objectName: "rowCard"
            anchors.fill: parent
            color: Theme.plate
            now: row.now
            createExtrasAhead: false
            // "Clear" is beside it: never two ways to delete next to each other
            closable: d.offset === 0 && !swipe.active
            appName: row.model.appName
            appIcon: row.model.appIcon
            desktopEntry: row.model.desktopEntry
            title: row.model.summary
            body: row.model.body
            time: row.model.time
            image: row.model.image
            actions: row.model.actions
            actionIcons: row.model.actionIcons
            files: row.model.files
            hasDefaultAction: row.model.hasDefaultAction
            inlineReply: row.model.inlineReply
            replyPlaceholder: row.model.replyPlaceholder
            replySubmitText: row.model.replySubmitText
            urgency: row.model.urgency
            originName: row.model.originName
            waiting: row.stacked ? row.model.groupCount - 1 : 0

            onDismissed: d.clear()
            onActionInvoked: key => row.actionInvoked(key)
            onReplied: text => row.replied(text)
            onFileOpened: url => row.fileOpened(url)

            TapHandler {
                id: tap

                longPressThreshold: 0.45
                cursorShape: Qt.PointingHandCursor
                onTapped: {
                    if (d.revealed) {
                        row.closeReveal()
                    } else if (row.anotherRevealed) {
                        row.attentionTaken()
                    } else if (row.stacked) {
                        row.groupToggled(row.model.groupKey)
                    } else if (card.hasDefaultAction) {
                        row.defaultInvoked()
                    } else if (card.canExpand) {
                        card.setExpanded(!card.expanded)
                    }
                }
                onLongPressed: {
                    if (!row.stacked && !d.revealed && !row.anotherRevealed && card.canExpand)
                        card.setExpanded(true)
                }
            }

            // Sideways only: up and down belong to the list
            DragHandler {
                id: swipe

                target: null
                yAxis.enabled: false
                enabled: !card.replyOpen
                onActiveChanged: {
                    if (active) {
                        settle.stop()
                        flyOut.stop()
                        restore.stop()
                        d.dragStart = mover.x
                        row.attentionTaken()
                    } else {
                        d.moveTo(SwipeRules.settle(d.offset, centroid.velocity.x, d.revealWidth, d.commitWidth))
                    }
                }
                onActiveTranslationChanged: {
                    if (active)
                        d.follow(activeTranslation.x)
                }
            }
        }
    }

    // --- Movement ---
    //
    // On the GUI thread, unlike the banner: the button beside the card follows it frame by frame, and
    // an Animator would show the card moving without it. Only these two rectangles change.

    NumberAnimation {
        id: settle

        target: mover
        property: "x"
        duration: 280
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: flyOut

        NumberAnimation {
            id: flyOutX

            target: mover
            property: "x"
            duration: 200
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                d.clear()
                restore.start()
            }
        }
    }

    // Still here after being cleared (the service is away): back in its place
    Timer {
        id: restore

        interval: 900
        onTriggered: row.closeReveal()
    }
}
