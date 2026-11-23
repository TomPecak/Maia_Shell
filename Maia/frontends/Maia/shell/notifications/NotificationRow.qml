pragma ComponentBehavior: Bound

import QtQuick

import MaiaFrontend

// One row of the notification center: a notification, or the stack of an application.
//
//   tap             a stack unfolds; else the default action (without one: expands)
//   swipe sideways  deleted (a stack: all of it), with a red "Clear" showing under it
//   long press      expands
//
// An unfolded group has a header with its name, "Show less" and "Clear". `model` is a row of
// NotificationGroupsModel. Says what was asked: NotificationCenterSheet.qml does it.
Item {
    id: row

    required property var model
    // The moment "5 min ago" is counted from
    property date now: new Date()

    readonly property alias card: card
    readonly property bool stacked: model.groupHead && !model.groupExpanded && model.groupCount > 1
    readonly property bool hasHeader: model.groupHead && model.groupExpanded

    signal groupToggled(string key)
    signal groupCleared(string key)
    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string key)
    signal replied(string text)
    signal fileOpened(string url)

    implicitHeight: mover.y + mover.height + (stacked ? d.stackDepth : 0) + d.gap
    height: implicitHeight

    Component.onCompleted: d.ready = true

    QtObject {
        id: d

        property bool ready: false
        readonly property int gap: 10
        // How far the plates of a stack show below the card
        readonly property int stackDepth: 14
        readonly property int headerHeight: 44

        function released(velocity) {
            const distance = mover.x
            const far = Math.abs(distance) > row.width * 0.35
            // A flick counts only from some distance: this deletes, a slip of the finger must not
            const fast = Math.abs(velocity) > 600 && Math.abs(distance) > 48 && velocity * distance > 0
            if (far || fast) {
                flyOutX.to = (distance > 0 ? 1 : -1) * (row.width + 24)
                flyOut.start()
            } else {
                snapBack.start()
            }
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

    // --- The plates of a stack, under the card ---

    Rectangle {
        objectName: "stackPlate"
        x: 20
        y: mover.y + mover.height - height + d.stackDepth
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
        y: mover.y + mover.height - height + d.stackDepth / 2
        width: row.width - 20
        height: 40
        radius: 20
        visible: row.stacked
        color: Theme.plate
        opacity: 0.8
        border.width: 1
        border.color: Theme.hairline
    }

    // --- Shows under the card while it is swiped ---

    Rectangle {
        y: mover.y
        width: row.width
        height: mover.height
        radius: card.radius
        visible: mover.x !== 0
        color: Theme.red
        opacity: Math.min(1, Math.abs(mover.x) / 60)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: mover.x > 0 ? parent.left : undefined
            anchors.right: mover.x < 0 ? parent.right : undefined
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            text: qsTr("Clear")
            color: "white"
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
    }

    // --- The card ---

    Item {
        id: mover

        y: header.height
        width: row.width
        height: card.targetHeight
        scale: tap.pressed && !swipe.active ? 0.98 : 1

        Behavior on height {
            enabled: d.ready

            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }

        NotificationCard {
            id: card

            objectName: "rowCard"
            anchors.fill: parent
            color: Theme.plate
            now: row.now
            createExtrasAhead: false
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
                    if (row.stacked)
                        row.groupToggled(row.model.groupKey)
                    else if (card.hasDefaultAction)
                        row.defaultInvoked()
                    else if (card.canExpand)
                        card.setExpanded(!card.expanded)
                }
                onLongPressed: {
                    if (!row.stacked && card.canExpand)
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
                        snapBack.stop()
                        restore.stop()
                    } else {
                        d.released(centroid.velocity.x)
                    }
                }
                onActiveTranslationChanged: {
                    if (active)
                        mover.x = activeTranslation.x
                }
            }
        }
    }

    // --- Movement, on the render thread ---

    XAnimator {
        id: snapBack

        target: mover
        to: 0
        duration: 240
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: flyOut

        XAnimator {
            id: flyOutX

            target: mover
            duration: 180
            easing.type: Easing.InCubic
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
        onTriggered: snapBack.start()
    }
}
