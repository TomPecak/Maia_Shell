import QtQuick
import QtQuick.Layouts

import LumenFrontend

// A page without its content says why and what to do: icon, title, explanation, one action
ColumnLayout {
    id: empty

    property string iconName
    property string title
    property string description
    property string actionText

    signal actionClicked()

    Layout.fillWidth: true
    Layout.topMargin: 48
    spacing: Theme.spacingM

    LIcon {
        iconName: empty.iconName
        size: 64
        tint: Theme.textTertiary
        Layout.alignment: Qt.AlignHCenter
    }

    LText {
        text: empty.title
        font.pixelSize: Theme.fontSubtitle
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
    }

    LText {
        visible: empty.description.length > 0
        text: empty.description
        color: Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: 480
        Layout.alignment: Qt.AlignHCenter
    }

    AccentButton {
        visible: empty.actionText.length > 0
        text: empty.actionText
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Theme.spacingS
        onClicked: empty.actionClicked()
    }
}
