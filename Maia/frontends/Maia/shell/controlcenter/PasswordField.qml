import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// A text field for a password or a user name, with an eye to show what was typed
Rectangle {
    id: field

    property alias text: input.text
    property string placeholderText
    property bool hidden: true
    readonly property alias input: input

    signal accepted()

    implicitHeight: 36
    radius: 10
    color: Theme.fill
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.accent

    TextInput {
        id: input

        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: eye.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        echoMode: field.hidden && !eye.revealed ? TextInput.Password : TextInput.Normal
        color: Theme.label
        selectionColor: Theme.accent
        font.pixelSize: 14
        clip: true
        onAccepted: field.accepted()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text.length === 0
            text: field.placeholderText
            color: Theme.tertiaryLabel
            font.pixelSize: 14
        }
    }

    Item {
        id: eye

        property bool revealed: false

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: field.hidden ? 26 : 0
        height: 26
        visible: field.hidden

        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Show password")
        Accessible.checked: revealed

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: Qt.resolvedUrl("../../assets/icons/view-preview-symbolic.svg")
            isMask: true
            color: eye.revealed ? Theme.accent : Theme.secondaryLabel
        }

        MouseArea {
            anchors.fill: parent
            onClicked: eye.revealed = !eye.revealed
        }
    }
}
