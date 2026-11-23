pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects

import Maia.Backend as Maia
import Maia.Notifications.Center

import MaiaFrontend

// The notification center, opened by the time in the Control Center's button: every notification of
// the session, by application, the newest first (a stack per application, as on iPadOS).
//
// A panel in the corner of that button, so the pointer's way to it is short (Fitts's law). It grows
// out of the corner like the Control Center and, like it, makes the screen modal: a click outside,
// Escape or the button closes it. What opens something elsewhere (the default action, an action, a
// file) closes it too; an answer does not, so that the next one can be read.
//
// Performance: the list is ready before it opens, the panel moves on the render thread, and only
// the rows on screen exist.
//
// Fills the whole window; the input region of the window covers it only while it is shown.
Item {
    id: sheet

    property bool open: false
    // A NotificationGroupsModel
    property var groups: null
    // Edge of the dock and the strip it reserves there, as in ControlCenter.qml
    property int dockEdge: Qt.TopEdge
    property real dockStrip: 0

    // Asks to be closed
    signal closeRequested()
    // Closed: the window that had the keyboard before should get it back
    signal dismissed()
    // A file or its folder
    signal openUrlRequested(string url)

    // Shown from opening until the closing animation has finished
    property bool shown: false
    property date now: new Date()
    // The row with its "Clear" open: one at a time
    property NotificationRow openRow: null

    readonly property int panelWidth: Math.min(440, width - 2 * screenMargin)
    readonly property real dockGap: 12
    readonly property real screenMargin: 16
    readonly property bool atRight: dockEdge !== Qt.LeftEdge
    readonly property bool atBottom: dockEdge === Qt.BottomEdge

    visible: shown

    onOpenChanged: open ? d.show() : d.hide()

    // Escape closes what was opened last: an open "Clear", then the panel
    Keys.onEscapePressed: {
        if (sheet.openRow)
            sheet.openRow.closeReveal()
        else
            sheet.closeRequested()
    }

    // Takes the keyboard while it is open
    Item {
        id: keyHandler

        focus: true
    }

    // "5 min ago" stays true while it is open; nothing ticks while it is closed
    Timer {
        interval: 30000
        repeat: true
        running: sheet.shown
        onTriggered: sheet.now = new Date()
    }

    // --- Dimming ---

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: Theme.controlCenterScrim
        opacity: 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: sheet.closeRequested()
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    // --- The panel ---

    RectangularShadow {
        anchors.fill: panel
        radius: panel.radius
        offset.y: 8
        blur: 32
        color: Theme.shadow
        opacity: panel.opacity
        scale: panel.scale
        transformOrigin: panel.transformOrigin
    }

    Rectangle {
        id: panel

        objectName: "notificationCenterPanel"
        width: sheet.panelWidth
        height: sheet.height - y - (sheet.atBottom ? sheet.dockStrip + sheet.dockGap : sheet.screenMargin)
        x: sheet.dockEdge === Qt.LeftEdge ? sheet.dockStrip + sheet.dockGap
         : sheet.dockEdge === Qt.RightEdge ? sheet.width - sheet.dockStrip - sheet.dockGap - width
         : sheet.width - sheet.screenMargin - width
        y: sheet.dockEdge === Qt.TopEdge ? sheet.dockStrip + sheet.dockGap : sheet.screenMargin
        radius: 28
        color: Theme.surface
        border.width: 1
        border.color: Theme.hairline
        opacity: 0
        scale: 0.94
        transformOrigin: sheet.atRight ? (sheet.atBottom ? Item.BottomRight : Item.TopRight)
                                       : (sheet.atBottom ? Item.BottomLeft : Item.TopLeft)

        // A click on the panel is not a click outside it
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: d.closeOpenRow()
            onWheel: function (wheel) { wheel.accepted = true }
        }

        // --- The title ---

        Item {
            id: title

            x: 20
            y: 12
            width: parent.width - 2 * x
            height: 52

            Text {
                anchors.left: parent.left
                anchors.right: clearAll.visible ? clearAll.left : parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Notifications")
                elide: Text.ElideRight
                color: Theme.label
                font.pixelSize: 26
                font.weight: Font.Bold
            }

            NotificationButton {
                id: clearAll

                objectName: "clearAllButton"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: sheet.groups !== null && sheet.groups.total > 0
                text: qsTr("Clear All")
                onClicked: NotificationCenter.dismissAll()
            }
        }

        // --- Do not disturb is on: why nothing pops up ---

        Rectangle {
            id: quietNote

            objectName: "quietNote"
            x: 14
            y: title.y + title.height + 2
            width: parent.width - 2 * x
            height: visible ? 40 : 0
            radius: 14
            visible: NotificationCenter.doNotDisturbActive
            color: Theme.fill

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                anchors.verticalCenter: parent.verticalCenter
                text: NotificationCenter.doNotDisturb ? qsTr("Do Not Disturb is on")
                                                      : qsTr("Kept quiet by an application")
                elide: Text.ElideRight
                color: Theme.secondaryLabel
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        // --- The list ---

        ListView {
            id: list

            objectName: "notificationList"
            x: 14
            y: quietNote.y + quietNote.height + (quietNote.visible ? 10 : 0)
            width: parent.width - 2 * x
            height: parent.height - y - 4
            clip: true
            cacheBuffer: 320
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            model: sheet.groups

            // Scrolling leaves an open "Clear" behind
            onMovementStarted: d.closeOpenRow()

            ScrollIndicator.vertical: ScrollIndicator {
            }

            delegate: NotificationRow {
                id: rowDelegate

                width: list.width
                now: sheet.now
                anotherRevealed: sheet.openRow !== null && sheet.openRow !== rowDelegate

                onAttentionTaken: {
                    if (sheet.openRow !== rowDelegate)
                        d.closeOpenRow()
                }
                onRevealedChanged: {
                    if (revealed)
                        sheet.openRow = rowDelegate
                    else if (sheet.openRow === rowDelegate)
                        sheet.openRow = null
                }

                onGroupToggled: key => sheet.groups.toggleGroup(key)
                onGroupCleared: key => sheet.groups.dismissGroup(key)
                onDismissed: NotificationCenter.dismiss(rowDelegate.model.notificationId)
                onDefaultInvoked: {
                    NotificationCenter.invokeAction(rowDelegate.model.notificationId, "default", rowDelegate.Window.window)
                    sheet.closeRequested()
                }
                onActionInvoked: key => {
                    NotificationCenter.invokeAction(rowDelegate.model.notificationId, key, rowDelegate.Window.window)
                    sheet.closeRequested()
                }
                onReplied: text => {
                    NotificationCenter.reply(rowDelegate.model.notificationId, text, rowDelegate.Window.window)
                    keyHandler.forceActiveFocus()
                }
                onFileOpened: url => {
                    sheet.openUrlRequested(url)
                    sheet.closeRequested()
                }

                // A closed answer field gives Escape back to the panel
                Connections {
                    target: rowDelegate.card

                    function onReplyOpenChanged() {
                        if (!rowDelegate.card.replyOpen)
                            keyHandler.forceActiveFocus()
                    }
                }
            }

            // Not while closed: nobody would see them
            add: sheet.shown ? addTransition : null
            remove: sheet.shown ? removeTransition : null
            displaced: sheet.shown ? displacedTransition : null
            move: sheet.shown ? displacedTransition : null

            // Inside a view's transitions Animators would leave a new item invisible
            Transition {
                id: addTransition

                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 240; easing.type: Easing.OutCubic }
            }
            Transition {
                id: removeTransition

                NumberAnimation { property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutQuad }
            }
            Transition {
                id: displacedTransition

                NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutCubic }
                // A row caught by a transition that was cut short comes back whole
                NumberAnimation { property: "opacity"; to: 1; duration: 120 }
                NumberAnimation { property: "scale"; to: 1; duration: 120 }
            }
        }

        Column {
            objectName: "emptyState"
            anchors.centerIn: list
            spacing: 6
            visible: sheet.groups === null || sheet.groups.total === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("No Notifications")
                color: Theme.secondaryLabel
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("New ones will appear here")
                color: Theme.tertiaryLabel
                font.pixelSize: 13
            }
        }
    }

    // --- Opening and closing, on the render thread ---

    ParallelAnimation {
        id: openAnimation

        OpacityAnimator { target: scrim; to: 1; duration: 220; easing.type: Easing.OutQuad }
        OpacityAnimator { target: panel; to: 1; duration: 180; easing.type: Easing.OutQuad }
        ScaleAnimator {
            target: panel
            to: 1
            duration: 420
            easing.type: Easing.OutBack
            easing.overshoot: 0.9
        }
    }

    ParallelAnimation {
        id: closeAnimation

        OpacityAnimator { target: scrim; to: 0; duration: 220; easing.type: Easing.OutQuad }
        OpacityAnimator { target: panel; to: 0; duration: 180; easing.type: Easing.OutQuad }
        ScaleAnimator { target: panel; to: 0.94; duration: 220; easing.type: Easing.OutCubic }

        onFinished: {
            if (sheet.open)
                return
            sheet.shown = false
            if (sheet.groups)
                sheet.groups.collapseAll()
            list.positionViewAtBeginning()
        }
    }

    QtObject {
        id: d

        function show() {
            closeAnimation.stop()
            if (!sheet.shown) {
                scrim.opacity = 0
                panel.opacity = 0
                panel.scale = 0.94
            }
            sheet.now = new Date()
            sheet.shown = true
            openAnimation.restart()
            if (sheet.Window.window)
                sheet.Window.window.requestActivate()
            keyHandler.forceActiveFocus()
        }

        function closeOpenRow() {
            if (sheet.openRow)
                sheet.openRow.closeReveal()
        }

        function hide() {
            closeOpenRow()
            openAnimation.stop()
            closeAnimation.restart()
            sheet.dismissed()
        }
    }
}
