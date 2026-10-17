import QtQuick
import QtQuick.Layouts

import ".."

// Notification in the notification center: application, time, title and text.
// The close button appears on hover.
Card {
    id: card

    property string appName
    property string iconName
    property string title
    property string body
    property string time

    signal dismissed()

    implicitHeight: content.implicitHeight + 2 * Theme.spacingM

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingXS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            LIcon {
                size: 16
                iconName: card.iconName
                tinted: card.iconName.endsWith("-symbolic")
            }

            LText {
                Layout.fillWidth: true
                text: card.appName
                font.pixelSize: Theme.fontCaption
                color: Theme.textSecondary
            }

            LText {
                text: card.time
                font.pixelSize: Theme.fontCaption
                color: Theme.textTertiary
                visible: !hover.hovered
            }

            SubtleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                padding: 0
                visible: hover.hovered
                Accessible.name: qsTr("Dismiss notification")
                contentItem: Item { LIcon { anchors.centerIn: parent; size: 12; iconName: "window-close-symbolic" } }
                onClicked: card.dismissed()
            }
        }

        LText {
            Layout.fillWidth: true
            text: card.title
            font.weight: Font.DemiBold
        }

        LText {
            Layout.fillWidth: true
            text: card.body
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
    }
}
