import QtQuick
import QtQuick.Layouts

import LumenFrontend

// Windows 11 selector bar: a row of text tabs, the selected one bold with an accent line under it
// that slides to the new tab.
Item {
    id: bar

    property var model: []
    property int currentIndex: 0

    implicitHeight: 40
    Layout.fillWidth: true

    Row {
        id: tabs

        height: parent.height
        spacing: Theme.spacingS

        Repeater {
            model: bar.model

            SubtleButton {
                id: tab

                required property string modelData
                required property int index

                height: tabs.height
                width: label.implicitWidth + 2 * Theme.spacingM
                onClicked: bar.currentIndex = index

                contentItem: LText {
                    id: label
                    text: tab.modelData
                    font.weight: bar.currentIndex === tab.index ? Font.DemiBold : Font.Normal
                    color: bar.currentIndex === tab.index ? Theme.textPrimary : Theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    Rectangle {
        readonly property Item tab: tabs.children[bar.currentIndex] ?? null

        x: tab ? tab.x + (tab.width - width) / 2 : 0
        width: tab ? Math.max(16, tab.width - 2 * Theme.spacingM) : 0
        height: 3
        radius: 1.5
        anchors.bottom: parent.bottom
        color: Theme.accent

        Behavior on x { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }
        Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }
    }
}
