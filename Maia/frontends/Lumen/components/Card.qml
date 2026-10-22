import QtQuick

import LumenFrontend

// Card placed on a flyout surface: a slightly lighter (or darker) area with a hairline border
Rectangle {
    radius: Theme.radiusMedium
    color: Theme.card
    border.width: 1
    border.color: Theme.stroke

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
}
