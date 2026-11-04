import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

import "Texts.js" as Texts

// "Share network" (docs #15): the QR code with the name and password. The password is read when
// the dialog opens (polkit may ask), never kept.
ContentDialog {
    id: dialog

    property string uuid

    function openFor(uuid) {
        dialog.uuid = uuid
        qr.code = null
        qr.name = ""
        qr.security = ""
        qr.password = ""
        qr.loading = true
        dialog.error = ""
        open()
        NetworkControl.settings(uuid, (result, settings) => {
            if (result.ok) {
                qr.name = settings.wifi.ssid
                qr.security = Texts.security(settings.security.security)
            }
        })
        NetworkControl.secrets(uuid, (result, secrets) => {
            if (result.ok)
                qr.password = NetworkControl.secretValue(secrets, Network.SecretKey.WifiPassword)
                              || NetworkControl.secretValue(secrets, Network.SecretKey.WepKey)
        })
        NetworkControl.qrCode(uuid, (result, code) => {
            qr.loading = false
            if (result.ok)
                qr.code = code
            else
                dialog.error = Texts.error(result)
        })
    }

    onClosed: qr.password = ""

    title: qsTr("Share network")
    primaryText: qsTr("Done")
    secondaryText: ""
    onAccepted: close()

    QrCard { id: qr }
}
