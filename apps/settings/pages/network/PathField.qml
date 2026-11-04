import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings

import "Texts.js" as Texts

// A file path (certificate, key, PAC file) typed or chosen with "Browse…"
FormField {
    id: field

    property string path
    property var nameFilters: [qsTr("Certificates (*.pem *.crt *.cer *.der *.p12 *.pfx *.key)"), qsTr("All files (*)")]

    signal edited(string path)

    RowLayout {
        spacing: Theme.spacingS
        Layout.fillWidth: true

        PasswordField {
            hidden: false
            text: field.path
            placeholderText: qsTr("None")
            Layout.fillWidth: true
            Accessible.name: field.label
            onTextEdited: field.edited(text.trim())
        }

        StandardButton {
            text: qsTr("Browse…")
            onClicked: dialog.open()
        }
    }

    FileDialog {
        id: dialog

        title: field.label
        nameFilters: field.nameFilters
        onAccepted: field.edited(Texts.pathOf(selectedFile))
    }
}
