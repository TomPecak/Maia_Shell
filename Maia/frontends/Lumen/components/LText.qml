import QtQuick

import ".."

// Text with the typography and colors of the theme
Text {
    color: Theme.textPrimary
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBody
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter

    Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
}
