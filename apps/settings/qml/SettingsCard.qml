import QtQuick
import QtQuick.Layouts

import LumenFrontend

// One setting: icon, title, description and its control at the right (a switch, a button, a
// value). clickable: the whole card is a target (larger than its control, Fitts) and shows a
// chevron when it opens something.
Rectangle {
    id: card

    property string iconName
    property string title
    property string description
    property color descriptionColor: Theme.textSecondary
    property bool clickable: false
    property bool chevron: clickable
    // The controls at the right
    default property alias trailing: trailingRow.data
    // Content under the row (e.g. the details of a password form)
    property alias below: belowColumn.data
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: row.height + (belowColumn.visibleChildren.length > 0 ? belowColumn.implicitHeight + Theme.spacingL : 0)
    radius: Theme.radiusSmall
    color: card.clickable && mouse.pressed ? Theme.subtlePressed : card.clickable && mouse.containsMouse ? Qt.tint(Theme.card, Theme.subtleHover) : Theme.card
    border.width: 1
    border.color: Theme.stroke
    opacity: enabled ? 1 : 0.5

    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: card.clickable
        enabled: card.clickable
        cursorShape: card.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.clicked()
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        height: Math.max(card.description.length > 0 ? 68 : 52, implicitHeight + 2 * Theme.spacingM)
        spacing: Theme.spacingL

        LIcon {
            visible: card.iconName.length > 0
            iconName: card.iconName
            size: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            LText {
                text: card.title
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            LText {
                visible: card.description.length > 0
                text: card.description
                color: card.descriptionColor
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Row {
            id: trailingRow

            spacing: Theme.spacingS
            Layout.alignment: Qt.AlignVCenter
        }

        LIcon {
            visible: card.chevron
            iconName: "go-next-symbolic"
            size: 16
            tint: Theme.textSecondary
            Layout.alignment: Qt.AlignVCenter
        }
    }

    ColumnLayout {
        id: belowColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: row.bottom
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        spacing: Theme.spacingM
    }
}
