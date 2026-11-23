import QtQuick

import MaiaFrontend

// The progress of a job as a bar. A full-width fill slides in from the left on the render thread, so
// that a step of the progress costs no layout and no work on the GUI thread. A job that does not
// tell its share has a moving piece, which runs only while the bar is seen.
Rectangle {
    id: bar

    // 0 .. 100, -1 unknown
    property int percent: -1
    property color tint: Theme.accent
    // Not paused: the piece of an unknown share moves
    property bool moving: true

    implicitHeight: 5
    radius: height / 2
    color: Theme.fill
    clip: true

    Rectangle {
        id: fill

        objectName: "jobBarFill"
        x: -bar.width * (1 - Math.max(0, Math.min(100, bar.percent)) / 100)
        width: bar.width
        height: bar.height
        radius: height / 2
        visible: bar.percent >= 0
        color: bar.tint

        Behavior on x {
            // Not while the bar takes its width: a new or resized bar is simply right
            enabled: bar.width > 0 && bar.visible

            XAnimator { duration: 240; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: piece

        objectName: "jobBarPiece"
        width: bar.width / 4
        height: bar.height
        radius: height / 2
        visible: bar.percent < 0
        color: bar.tint

        XAnimator on x {
            running: piece.visible && bar.moving
            from: -piece.width
            to: bar.width
            duration: 1300
            loops: Animation.Infinite
        }
    }
}
