import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Item of LMenu: icon, text and an arrow when the item opens a submenu.
// Disabled items are dimmed and do not react to the mouse.
T.AbstractButton {
    id: item

    property string iconName
    property color iconColor: Theme.textPrimary
    property bool hasSubmenu: false
    // Keyboard shortcut shown on the right, e.g. "Ctrl+C"
    property string shortcut
    // Keeps the hover fill while the submenu of the item is open
    property bool highlighted: false

    width: parent ? parent.width : implicitWidth
    implicitHeight: 32
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    leftInset: Theme.spacingXS
    rightInset: Theme.spacingXS
    leftPadding: Theme.spacingL
    rightPadding: Theme.spacingM

    Accessible.role: hasSubmenu ? Accessible.ButtonMenu : Accessible.MenuItem
    Accessible.name: text

    background: Rectangle {
        radius: Theme.radiusSmall
        color: !item.enabled ? "transparent"
             : item.pressed ? Theme.subtlePressed
             : (item.hovered || item.highlighted) ? Theme.subtleHover
             : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    contentItem: Item {
        LIcon {
            id: icon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            iconName: item.iconName
            size: 16
            tint: item.enabled ? item.iconColor : Theme.textTertiary
        }

        LText {
            anchors.left: parent.left
            anchors.leftMargin: 16 + Theme.spacingM
            anchors.right: shortcutLabel.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            color: item.enabled ? Theme.textPrimary : Theme.textTertiary
        }

        LText {
            id: shortcutLabel

            anchors.right: arrow.visible ? arrow.left : parent.right
            anchors.rightMargin: arrow.visible ? Theme.spacingS : 0
            anchors.verticalCenter: parent.verticalCenter
            text: item.shortcut
            font.pixelSize: Theme.fontCaption
            color: Theme.textTertiary
        }

        LIcon {
            id: arrow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: item.hasSubmenu
            iconName: "go-next-symbolic"
            size: 12
            tint: item.enabled ? Theme.textSecondary : Theme.textTertiary
        }
    }
}
