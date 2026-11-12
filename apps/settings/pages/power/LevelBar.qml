import QtQuick

import LumenFrontend

// A battery's level as GNOME shows it: a bar with the percentage next to it. low: drawn in the
// critical color (the percentage is still there, the color alone does not carry the meaning).
Row {
    id: bar

    property real percentage
    property bool low: false
    property int barWidth: 160

    spacing: Theme.spacingM

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: bar.barWidth
        height: 6
        radius: 3
        color: Theme.controlStrong

        Rectangle {
            width: Math.max(height, parent.width * Math.max(0, Math.min(100, bar.percentage)) / 100)
            height: parent.height
            radius: parent.radius
            color: bar.low ? Theme.critical : Theme.accent

            Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard } }
        }
    }

    LText {
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        horizontalAlignment: Text.AlignRight
        text: qsTr("%1 %").arg(Math.round(bar.percentage))
        font.features: { "tnum": 1 }
    }
}
