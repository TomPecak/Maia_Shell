import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Tooltip of the File Explorer toolbars: a small card under the control, after a short delay
T.ToolTip {
    id: tip

    x: parent ? Math.round((parent.width - implicitWidth) / 2) : 0
    y: parent ? parent.height + Theme.spacingXS : 0
    delay: 600
    timeout: 6000
    margins: Theme.spacingS
    padding: Theme.spacingS
    leftPadding: Theme.spacingM
    rightPadding: Theme.spacingM

    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    implicitHeight: implicitContentHeight + topPadding + bottomPadding

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast; easing.type: Theme.easingEnter }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Theme.easingExit }
    }

    contentItem: LText {
        text: tip.text
        font.pixelSize: Theme.fontCaption
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.surface
        border.width: 1
        border.color: Theme.stroke
    }
}
