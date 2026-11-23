import QtQuick

import MaiaFrontend

// The answer field of a notification banner: a pill with the text and a round send button. Enter
// sends, Escape gives up.
Rectangle {
    id: field

    property string placeholderText
    property string submitText
    readonly property alias input: input
    readonly property bool canSend: input.text.trim().length > 0

    signal sent(string text)
    signal cancelled()

    function send() {
        if (!canSend)
            return
        const text = input.text
        input.text = ""
        field.sent(text)
    }

    implicitHeight: 44
    radius: 22
    color: Theme.fill
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.accent

    TextInput {
        id: input

        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: sendButton.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.label
        selectionColor: Theme.accent
        selectedTextColor: "white"
        font.pixelSize: 15
        clip: true
        Accessible.role: Accessible.EditableText
        Accessible.name: placeholder.text

        Keys.onReturnPressed: field.send()
        Keys.onEnterPressed: field.send()
        Keys.onEscapePressed: field.cancelled()

        Text {
            id: placeholder

            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text.length === 0
            text: field.placeholderText.length > 0 ? field.placeholderText : qsTr("Type a reply…")
            elide: Text.ElideRight
            color: Theme.secondaryLabel
            font: input.font
        }
    }

    BannerButton {
        id: sendButton

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        round: true
        plateSize: 32
        prominent: field.canSend
        enabled: field.canSend
        opacity: field.canSend ? 1 : 0.4
        glyph: Qt.resolvedUrl("../../assets/icons/go-up-symbolic.svg")
        text: field.submitText.length > 0 ? field.submitText : qsTr("Send")
        onClicked: field.send()
    }
}
