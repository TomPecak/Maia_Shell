import QtQuick
import QtQuick.Layouts

import LumenFrontend

// A label above its field (scanned top to bottom, the label is read first) and a line under it
// for help or an error. The field sets Layout.fillWidth itself when it should be as wide.
ColumnLayout {
    id: field

    property string label
    property string help
    property string error
    default property alias field: slot.data

    Layout.fillWidth: true
    spacing: Theme.spacingXS

    LText {
        visible: field.label.length > 0
        text: field.label
        font.pixelSize: Theme.fontCaption
        color: Theme.textSecondary
    }

    ColumnLayout {
        id: slot

        Layout.fillWidth: true
        spacing: Theme.spacingXS
    }

    LText {
        visible: text.length > 0
        text: field.error.length > 0 ? field.error : field.help
        color: field.error.length > 0 ? Theme.critical : Theme.textTertiary
        font.pixelSize: Theme.fontCaption
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
}
