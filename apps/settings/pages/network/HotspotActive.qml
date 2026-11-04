import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

import "Texts.js" as Texts

// The running hotspot on the Wi-Fi page: its QR code, name, password, and "Turn off"
SettingsGroup {
    id: group

    property string deviceId
    property string uuid

    title: qsTr("Hotspot is on")

    function load() {
        if (!visible || uuid.length === 0)
            return
        qr.loading = true
        NetworkControl.settings(uuid, (result, settings) => {
            if (result.ok) {
                qr.name = settings.wifi.ssid
                qr.security = Texts.security(settings.security.security)
            }
        })
        NetworkControl.secrets(uuid, (result, secrets) => {
            if (result.ok)
                qr.password = NetworkControl.secretValue(secrets, Network.SecretKey.WifiPassword)
        })
        NetworkControl.qrCode(uuid, (result, code) => {
            qr.loading = false
            if (result.ok)
                qr.code = code
        })
    }

    onVisibleChanged: load()
    onUuidChanged: load()

    SettingsCard {
        below: QrCard {
            id: qr
            Layout.bottomMargin: Theme.spacingS
        }

        title: qsTr("Other devices can connect to this network")
        iconName: "network-wireless-hotspot-symbolic"

        StandardButton {
            text: qsTr("Turn off")
            destructive: true
            onClicked: confirm.open()
        }
    }

    ContentDialog {
        id: confirm

        title: qsTr("Turn off the hotspot?")
        primaryText: qsTr("Turn off")
        onAccepted: {
            busy = true
            NetworkControl.stopHotspot(group.deviceId, result => {
                busy = false
                if (result.ok)
                    close()
                else
                    error = Texts.error(result)
            })
        }

        LText {
            text: qsTr("Devices connected to it lose their internet connection.")
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
