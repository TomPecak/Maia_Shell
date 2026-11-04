import QtQuick
import QtQuick.Layouts

import LumenFrontend

// Fluent info bar: a message inside the page, where it concerns (not a popup that hides
// the content). severity: "info", "success", "warning", "error".
Rectangle {
    id: bar

    property string severity: "info"
    property string title
    property string message
    property string actionText
    property bool closable: false

    signal actionClicked()
    signal closeClicked()

    readonly property color tone: severity === "error" ? Theme.critical
                                : severity === "warning" ? (Theme.dark ? "#FCE100" : "#9D5D00")
                                : severity === "success" ? (Theme.dark ? "#6CCB5F" : "#0F7B0F")
                                : Theme.accent

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 2 * Theme.spacingM
    radius: Theme.radiusSmall
    color: Qt.rgba(tone.r, tone.g, tone.b, Theme.dark ? 0.14 : 0.10)
    border.width: 1
    border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.3)

    RowLayout {
        id: row

        anchors.fill: parent
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingM

        // A filled badge with a mark: the color alone does not carry the meaning
        Rectangle {
            implicitWidth: 18
            implicitHeight: 18
            radius: 9
            color: bar.tone
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1

            LText {
                anchors.centerIn: parent
                text: bar.severity === "success" ? "✓" : bar.severity === "info" ? "i" : "!"
                color: Theme.dark ? "#000000" : "#FFFFFF"
                font.pixelSize: 12
                font.weight: Font.Bold
            }
        }

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            LText {
                visible: bar.title.length > 0
                text: bar.title
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            LText {
                visible: bar.message.length > 0
                text: bar.message
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        StandardButton {
            visible: bar.actionText.length > 0
            text: bar.actionText
            onClicked: bar.actionClicked()
        }

        SubtleButton {
            visible: bar.closable
            implicitWidth: 32
            implicitHeight: 32
            Accessible.name: qsTr("Close")
            onClicked: bar.closeClicked()

            contentItem: Item {
                LIcon { anchors.centerIn: parent; iconName: "window-close-symbolic"; size: 14 }
            }
        }
    }
}
