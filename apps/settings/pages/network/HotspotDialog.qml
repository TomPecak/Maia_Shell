import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

import "Texts.js" as Texts

// "Turn on the hotspot?" (docs #16): what it does, the network it disconnects from, the name
// (the computer's name at first) and the password (empty: one is made).
ContentDialog {
    id: dialog

    property string deviceId
    property string ssid
    property string password

    function openFor(deviceId) {
        dialog.deviceId = deviceId
        nameField.text = NetworkControl.hostName()
        passwordField.text = ""
        open()
        nameField.forceActiveFocus()
    }

    WifiStatus { id: wifi }

    readonly property int ssidBytes: Texts.utf8Length(nameField.text)
    readonly property string nameError: nameField.text.trim().length === 0 ? qsTr("The network name cannot be empty.")
                                      : ssidBytes > 32 ? qsTr("The network name is too long.") : ""
    readonly property string passwordError: passwordField.text.length > 0 && !Texts.validWpaPassword(passwordField.text)
                                            ? qsTr("A password has 8 to 63 characters.") : ""

    title: qsTr("Turn on the hotspot?")
    primaryText: qsTr("Turn on")
    primaryEnabled: nameError.length === 0 && passwordError.length === 0

    onAccepted: {
        dialog.error = ""
        dialog.busy = true
        NetworkControl.startHotspot(dialog.deviceId, nameField.text.trim(), passwordField.text, (result, hotspot) => {
            dialog.busy = false
            if (result.ok)
                dialog.close()
            else
                dialog.error = Texts.error(result)
        })
    }

    LText {
        text: qsTr("Other devices can use this computer's internet connection through a Wi-Fi network it makes. The internet must come from elsewhere than Wi-Fi, such as a cable.")
        color: Theme.textSecondary
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    InfoBar {
        visible: wifi.connected && !wifi.hotspot
        severity: "warning"
        message: qsTr("The hotspot disconnects from %1: you cannot use the internet over Wi-Fi while it is on.").arg(wifi.networkName)
    }

    FormField {
        label: qsTr("Network name")
        error: nameField.text.length > 0 ? dialog.nameError : ""

        PasswordField {
            id: nameField
            hidden: false
            Layout.fillWidth: true
            Accessible.name: qsTr("Network name")
            Keys.onReturnPressed: dialog.accept()
        }
    }

    FormField {
        label: qsTr("Password")
        help: qsTr("Leave empty to have one made.")
        error: dialog.passwordError

        PasswordField {
            id: passwordField
            placeholderText: qsTr("Made automatically")
            Layout.fillWidth: true
            Accessible.name: qsTr("Password")
            Keys.onReturnPressed: dialog.accept()
        }
    }
}
