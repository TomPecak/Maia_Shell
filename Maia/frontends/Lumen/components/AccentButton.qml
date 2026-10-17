import QtQuick
import QtQuick.Templates as T

import ".."

// Filled button in the accent color, used for the main action of a view
T.Button {
    id: control

    hoverEnabled: true
    padding: Theme.spacingS
    leftPadding: Theme.spacingL
    rightPadding: Theme.spacingL

    implicitWidth: Math.max(implicitBackgroundWidth, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)

    contentItem: LText {
        text: control.text
        color: Theme.onAccent
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.pressed ? Theme.accentPressed : control.hovered ? Theme.accentHover : Theme.accent

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }
}
