import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// A network in reach: signal, name, state, padlock, and for saved or active networks the share
// (QR code) and details buttons. The row connects on a click; the active one opens its details.
SettingsCard {
    id: row

    required property string networkId
    required property string name
    required property string deviceId
    required property int security
    required property bool secure
    required property bool enterprise
    required property int strength
    required property int signalLevel
    required property bool known
    required property string connectionUuid
    required property bool active
    required property bool connecting

    signal activated()
    signal shareClicked()
    signal detailsClicked()

    iconName: Texts.signalIcon(signalLevel)
    title: name
    description: connecting ? qsTr("Connecting…")
               : active ? qsTr("Connected")
               : known ? qsTr("Saved")
               : enterprise ? qsTr("Enterprise network: needs your account")
               : ""
    descriptionColor: active ? Theme.accent : Theme.textSecondary
    clickable: !connecting
    chevron: false
    Accessible.name: name + (secure ? ", " + qsTr("secured") : "") + ", " + qsTr("signal %1 %").arg(strength)
    onClicked: activated()

    ProgressRing {
        visible: row.connecting
        width: 18
        height: 18
        thickness: 2
        value: 0.25
        anchors.verticalCenter: parent.verticalCenter
        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: row.connecting }
    }

    LIcon {
        visible: row.secure
        iconName: "lock-symbolic"
        size: 16
        tint: Theme.textSecondary
        anchors.verticalCenter: parent.verticalCenter
        // GNOME: "Secure network (WPA / WPA2 / WPA3)"
        ToolTipArea { text: qsTr("Secured: %1").arg(Texts.security(row.security)) }
    }

    IconButton {
        visible: row.known && !row.enterprise && row.security !== Network.Security.Leap
        iconName: "view-barcode-qr-symbolic"
        tip: qsTr("Share this network (QR code)")
        onClicked: row.shareClicked()
    }

    IconButton {
        visible: row.known || row.active
        iconName: "configure-symbolic"
        tip: qsTr("Network details")
        onClicked: row.detailsClicked()
    }
}
