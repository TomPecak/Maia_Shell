import QtQuick
import QtQuick.Templates as T

import LumenFrontend

// Text field for passwords (Fluent): dots, an eye button that shows the text while it is held
// down... or toggled (Windows 11 shows it while pressed; a click toggles here, kinder to a pointer),
// an accent underline while focused. hidden: false makes it a plain text field (e.g. an identity).
T.TextField {
    id: control

    property bool hidden: true
    property bool revealed: false
    // Shown in the critical color under the field when not empty
    property string errorText

    implicitWidth: 280
    implicitHeight: 34

    leftPadding: Theme.spacingM
    rightPadding: control.hidden ? 34 : Theme.spacingM

    color: Theme.textPrimary
    placeholderTextColor: Theme.textTertiary
    selectionColor: Theme.accent
    selectedTextColor: Theme.onAccent
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontBody
    verticalAlignment: TextInput.AlignVCenter
    echoMode: control.hidden && !control.revealed ? TextInput.Password : TextInput.Normal
    passwordCharacter: "•"
    inputMethodHints: control.hidden ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase : Qt.ImhNone

    LText {
        x: control.leftPadding
        width: control.availableWidth
        height: control.height
        text: control.placeholderText
        color: control.placeholderTextColor
        visible: !control.length && !control.preeditText
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: Theme.control
        border.width: 1
        border.color: control.errorText.length > 0 ? Theme.critical : Theme.stroke
        clip: true

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: control.activeFocus ? parent.width : 0
            height: 2
            color: control.errorText.length > 0 ? Theme.critical : Theme.accent

            Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
        }
    }

    SubtleButton {
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: control.height - 4
        padding: 0
        visible: control.hidden && control.length > 0
        focusPolicy: Qt.NoFocus
        Accessible.name: control.revealed ? qsTr("Hide password") : qsTr("Show password")
        onClicked: control.revealed = !control.revealed

        contentItem: Item {
            LIcon {
                anchors.centerIn: parent
                size: 16
                iconName: control.revealed ? "view-hidden-symbolic" : "view-visible-symbolic"
                tint: Theme.textSecondary
            }
        }
    }
}
