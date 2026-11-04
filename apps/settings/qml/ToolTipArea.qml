import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// A tooltip for its parent: shown after a short hover (not at once, so it does not get in the way)
Item {
    id: area

    property string text

    anchors.fill: parent

    HoverHandler { id: hover }

    T.ToolTip {
        visible: hover.hovered && area.text.length > 0
        delay: 600
        text: area.text
        y: -implicitHeight - Theme.spacingXS
        padding: Theme.spacingS
        leftPadding: Theme.spacingM
        rightPadding: Theme.spacingM

        contentItem: LText {
            text: area.text
            font.pixelSize: Theme.fontCaption
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.stroke
        }
    }
}
