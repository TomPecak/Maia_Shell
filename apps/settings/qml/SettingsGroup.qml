import QtQuick
import QtQuick.Layouts

import LumenFrontend

// Cards that belong together, under an optional header (Windows 11: 4 px between the cards of
// a group, a larger gap between groups, so the grouping is seen at once).
ColumnLayout {
    id: group

    property string title
    default property alias cards: list.data
    // Something at the right of the header (e.g. a scanning ring)
    property alias headerExtra: extra.data

    Layout.fillWidth: true
    spacing: Theme.spacingS

    RowLayout {
        Layout.fillWidth: true
        visible: group.title.length > 0

        LText {
            text: group.title
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }

        Row { id: extra; spacing: Theme.spacingS }
    }

    ColumnLayout {
        id: list

        Layout.fillWidth: true
        spacing: 4
    }
}
