import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// "Connect to a hidden network" (docs #14), also the details of a new Enterprise network in reach
// (#22): name, security and what it needs. Connect stays disabled until the details are complete,
// and a failure keeps the dialog open with the reason, so nothing typed is lost.
ContentDialog {
    id: dialog

    property string deviceId
    // true: a hidden network (the name is typed); false: a network in reach (name fixed)
    property bool hidden: true
    property var settings: null
    property int revision
    property int loaded
    // A saved hidden network chosen instead of a new one
    property string savedUuid

    function openNew(deviceId, ssid, security, hidden) {
        dialog.deviceId = deviceId
        dialog.hidden = hidden
        const s = NetworkControl.newSettings(ssid, security)
        s.wifi.hidden = hidden
        dialog.settings = s
        dialog.savedUuid = ""
        form.password = ""
        form.wepKey = ""
        form.leapPassword = ""
        ++dialog.loaded
        ++dialog.revision
        open()
    }

    title: hidden ? qsTr("Connect to a hidden network") : qsTr("Connect to “%1”").arg(settings ? settings.wifi.ssid : "")
    primaryText: qsTr("Connect")
    primaryEnabled: savedUuid.length > 0
                    || (revision >= 0 && settings && settings.wifi.ssid.length > 0 && Texts.utf8Length(settings.wifi.ssid) <= 32 && form.valid)

    SavedNetworksModel { id: saved }

    onAccepted: {
        dialog.error = ""
        dialog.busy = true
        const done = (result, uuid) => {
            dialog.busy = false
            if (result.ok) {
                dialog.close()
                SettingsApp.toast(qsTr("Connecting to %1…").arg(dialog.settings.wifi.ssid))
            } else {
                dialog.error = Texts.error(result)
            }
        }
        if (dialog.savedUuid.length > 0) {
            saved.activate(dialog.savedUuid, dialog.deviceId, done)
            return
        }
        dialog.settings.name = dialog.settings.wifi.ssid
        NetworkControl.connectWithSettings(dialog.deviceId, dialog.settings, form.secrets(), done)
    }

    LText {
        visible: dialog.hidden
        text: qsTr("Enter the name and the security of the network. It is saved, and this computer connects to it when it is in reach.")
        color: Theme.textSecondary
        wrapMode: Text.Wrap
        Layout.fillWidth: true
    }

    // A hidden network saved before can be chosen instead of typing it again
    FormField {
        id: connectionField

        readonly property var hiddenProfiles: {
            const list = [{ text: qsTr("New network"), value: "" }]
            for (let i = 0; i < saved.count; ++i) {
                const p = saved.get(saved.data(saved.index(i, 0), SavedNetworksModel.UuidRole))
                if (p.hidden)
                    list.push({ text: p.name, value: p.uuid })
            }
            return list
        }

        visible: dialog.hidden && hiddenProfiles.length > 1
        label: qsTr("Connection")

        ComboField {
            Layout.fillWidth: true
            model: connectionField.hiddenProfiles
            currentIndex: Math.max(0, indexOfValue(dialog.savedUuid))
            onActivated: dialog.savedUuid = currentValue
        }
    }

    FormField {
        visible: dialog.hidden && dialog.savedUuid.length === 0
        label: qsTr("Network name")
        error: {
            if (dialog.revision < 0 || !dialog.settings)
                return ""
            return Texts.utf8Length(dialog.settings.wifi.ssid) > 32 ? qsTr("A network name has at most 32 bytes.") : ""
        }

        PasswordField {
            hidden: false
            text: dialog.loaded >= 0 && dialog.settings ? dialog.settings.wifi.ssid : ""
            Layout.fillWidth: true
            Accessible.name: qsTr("Network name")
            onTextEdited: {
                dialog.settings.wifi.ssid = text
                dialog.settings.wifi.ssidBytes = undefined
                ++dialog.revision
            }
            Keys.onReturnPressed: dialog.accept()
        }
    }

    SecurityForm {
        id: form

        visible: dialog.savedUuid.length === 0
        security: dialog.settings ? dialog.settings.security : null
        revision: dialog.revision
        loaded: dialog.loaded
        onEdited: ++dialog.revision
    }
}
