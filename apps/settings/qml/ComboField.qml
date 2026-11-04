import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Fluent combo box. model: [{ text, value }]; currentValue / indexOfValue() as in Qt Quick Controls.
T.ComboBox {
    id: control

    textRole: "text"
    valueRole: "value"
    hoverEnabled: true
    leftPadding: Theme.spacingM
    rightPadding: 32

    implicitWidth: 240
    implicitHeight: 32
    opacity: enabled ? 1 : 0.45

    contentItem: LText {
        text: control.displayText
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    indicator: LIcon {
        x: control.width - width - Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        iconName: "go-down-symbolic"
        size: 12
        tint: Theme.textSecondary
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.pressed ? Theme.subtlePressed : control.hovered ? Qt.tint(Theme.control, Theme.subtleHover) : Theme.control
        border.width: 1
        border.color: control.visualFocus ? Theme.accent : Theme.stroke
    }

    delegate: T.ItemDelegate {
        id: item

        required property var modelData
        required property int index

        width: ListView.view.width
        implicitHeight: 36
        hoverEnabled: true
        highlighted: control.highlightedIndex === index

        contentItem: LText {
            leftPadding: Theme.spacingM
            text: item.modelData[control.textRole]
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: item.highlighted || item.hovered ? Theme.subtleHover : "transparent"

            Rectangle {
                visible: control.currentIndex === item.index
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 16
                radius: 1.5
                color: Theme.accent
            }
        }
    }

    popup: T.Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 2 * padding, 320)
        padding: 4

        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast } }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
        }

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.stroke
        }
    }
}
