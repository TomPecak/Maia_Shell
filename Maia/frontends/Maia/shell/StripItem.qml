import QtQuick

// Something that lives at one end of the strip the dock reserves (the power button at one end,
// the Control Center at the other). Horizontal or vertical, following the dock.
//
// It belongs to the edge of the dock. When the dock moves to another edge, it does not travel
// across the screen (small controls crossing the windows would pull the eye away from the dock,
// which is the main movement): it quickly shrinks and fades out at its old place, and after a short
// pause appears at the new one with a soft spring, already in its new orientation. The parent
// positions it by placedEdge, which changes only while it is invisible.
Item {
    id: item

    // Edge of the dock it belongs to
    property int edge: Qt.TopEdge
    // Edge it is placed at now: follows edge while it is invisible
    property int placedEdge: Qt.TopEdge

    readonly property bool vertical: placedEdge === Qt.LeftEdge || placedEdge === Qt.RightEdge

    // At start it simply is where it belongs
    Component.onCompleted: {
        placedEdge = edge
        d.ready = true
    }

    onEdgeChanged: {
        if (!d.ready) {
            placedEdge = edge
            return
        }
        // Started again when the edge changes once more while it moves: it disappears from
        // wherever it is and comes up at the newest edge
        moveAnimation.restart()
    }

    QtObject {
        id: d

        property bool ready: false
        // Scale it shrinks to and grows from
        readonly property real hiddenScale: 0.6
    }

    SequentialAnimation {
        id: moveAnimation

        // Leaving: short and accelerating, it is going away
        ParallelAnimation {
            ScaleAnimator { target: item; to: d.hiddenScale; duration: 150; easing.type: Easing.InCubic }
            OpacityAnimator { target: item; to: 0; duration: 150; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: item.placedEdge = item.edge
        }
        // A beat between leaving and arriving, so the appearance reads as one at the new place
        PauseAnimation { duration: 90 }
        // Arriving: a spring with a small overshoot, the opacity a little ahead of the size
        ParallelAnimation {
            ScaleAnimator {
                target: item
                from: d.hiddenScale
                to: 1
                duration: 420
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
            OpacityAnimator { target: item; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
    }
}
