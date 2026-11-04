import QtQuick
import QtQuick.Layouts

import LumenFrontend

// A short message at the bottom of the window with an optional action ("Network forgotten · Undo").
// Several messages in a row replace each other; the replaced one counts as dismissed.
Item {
    id: toast

    property string text
    property string actionText
    property var onAction: null
    property var onDismissed: null
    property bool shown: false

    function show(text, actionText, onAction, onDismissed) {
        finish(false)
        toast.text = text
        toast.actionText = actionText
        toast.onAction = onAction
        toast.onDismissed = onDismissed
        toast.shown = true
        timer.restart()
    }

    // acted: the action was clicked; else the message went away by itself
    function finish(acted) {
        if (!shown)
            return
        const callback = acted ? onAction : onDismissed
        shown = false
        timer.stop()
        onAction = null
        onDismissed = null
        if (callback)
            callback()
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    // Long enough to read and reach the action (WCAG 2.2.1: adjustable timing; hovering keeps it)
    Timer {
        id: timer
        interval: 6000
        onTriggered: if (!hover.hovered) toast.finish(false); else restart()
    }

    HoverHandler { id: hover }

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        width: row.implicitWidth + 2 * Theme.spacingL
        height: 44
        radius: Theme.radiusMedium
        color: Theme.surface
        border.width: 1
        border.color: Theme.stroke
        opacity: toast.shown ? 1 : 0
        y: toast.shown ? 0 : 12
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
        Behavior on y { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }

        RowLayout {
            id: row

            anchors.centerIn: parent
            spacing: Theme.spacingL

            LText { text: toast.text }

            SubtleButton {
                visible: toast.actionText.length > 0
                implicitHeight: 32
                implicitWidth: actionLabel.implicitWidth + 2 * Theme.spacingM
                onClicked: toast.finish(true)

                contentItem: LText {
                    id: actionLabel
                    text: toast.actionText
                    color: Theme.accent
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
