import QtQuick
import QtQuick.Templates as T

import ".."

// Rounded search field with a search icon. While focused it shows an accent underline.
T.TextField {
    id: control

    implicitWidth: 400
    implicitHeight: 40

    leftPadding: Theme.spacingL + 16 + Theme.spacingS
    rightPadding: Theme.spacingL

    color: Theme.textPrimary
    placeholderTextColor: Theme.textTertiary
    selectionColor: Theme.accent
    selectedTextColor: Theme.onAccent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBody
    verticalAlignment: TextInput.AlignVCenter

    LText {
        x: control.leftPadding
        width: control.availableWidth
        height: control.height
        text: control.placeholderText
        color: control.placeholderTextColor
        visible: !control.length && !control.preeditText
    }

    background: Rectangle {
        radius: height / 2
        color: Theme.control
        border.width: 1
        border.color: Theme.stroke
        clip: true

        LIcon {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.spacingL
            size: 16
            iconName: "system-search-symbolic"
            tint: Theme.textSecondary
        }

        // Accent underline while focused
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: control.activeFocus ? parent.width - parent.radius * 2 : 0
            height: 2
            radius: 1
            color: Theme.accent

            Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
        }
    }
}
