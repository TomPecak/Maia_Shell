import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// One Wi-Fi adapter on the Wi-Fi page: its switch and state, the actions, the networks it sees
// or, while it is a hotspot, the hotspot.
ColumnLayout {
    id: section

    required property WifiStatus wifi
    required property string deviceId
    required property int state
    required property int stateReason
    required property bool hotspot
    required property bool canHotspot
    required property bool scanning
    required property string activeConnectionUuid

    signal hiddenRequested(string deviceId)
    signal hotspotRequested(string deviceId)
    signal enterpriseRequested(string deviceId, string ssid, int security)
    signal shareRequested(string uuid)
    signal detailsRequested(string uuid, string deviceId, string networkId)

    readonly property bool connecting: state === Network.DeviceState.Connecting || state === Network.DeviceState.NeedAuth
    readonly property bool connected: state === Network.DeviceState.Connected

    spacing: Theme.spacingXL

    SavedNetworksModel { id: saved }

    SettingsGroup {
        SettingsCard {
            iconName: !section.wifi.enabled ? "network-wireless-disconnected-symbolic"
                    : section.hotspot ? "network-wireless-hotspot-symbolic"
                    : section.connecting ? "network-wireless-acquiring-symbolic"
                    : section.connected ? Texts.signalIcon(section.wifi.signalLevel)
                    : "network-wireless-signal-none-symbolic"
            title: qsTr("Wi-Fi")
            description: {
                if (!section.wifi.hardwareEnabled)
                    return qsTr("Turned off by a hardware switch")
                if (!section.wifi.enabled)
                    return qsTr("Off")
                if (section.hotspot)
                    return qsTr("Sharing this computer's connection as a hotspot")
                if (section.connecting)
                    return qsTr("Connecting to %1…").arg(section.wifi.networkName)
                if (section.connected) {
                    if (section.wifi.portal)
                        return qsTr("Connected to %1 · Sign-in needed").arg(section.wifi.networkName)
                    if (section.wifi.connectivity === Network.Connectivity.None || section.wifi.connectivity === Network.Connectivity.Limited)
                        return qsTr("Connected to %1 · No internet").arg(section.wifi.networkName)
                    return qsTr("Connected to %1").arg(section.wifi.networkName)
                }
                if (section.state === Network.DeviceState.Failed)
                    return Texts.reason(section.stateReason)
                return qsTr("Not connected")
            }

            LSwitch {
                checked: section.wifi.enabled
                enabled: section.wifi.canToggle
                Accessible.name: qsTr("Wi-Fi")
                onToggled: section.wifi.setEnabled(checked)
            }
        }
    }

    InfoBar {
        visible: section.wifi.portal && section.connected
        severity: "warning"
        title: qsTr("Sign in to the network")
        message: qsTr("This network asks you to sign in on its web page before you can use the internet.")
        actionText: qsTr("Sign in")
        onActionClicked: section.wifi.openPortal()
    }

    SettingsGroup {
        visible: section.wifi.enabled

        SettingsCard {
            iconName: "view-list-details-symbolic"
            title: qsTr("Saved networks")
            description: saved.count === 0 ? qsTr("None yet") : (saved.count === 1 ? qsTr("1 network") : qsTr("%1 networks").arg(saved.count))
            clickable: true
            onClicked: SettingsApp.push(Qt.resolvedUrl("SavedNetworksPage.qml"), {})
        }

        SettingsCard {
            iconName: "list-add-symbolic"
            title: qsTr("Connect to a hidden network")
            description: qsTr("A network that does not show its name")
            clickable: true
            onClicked: section.hiddenRequested(section.deviceId)
        }

        SettingsCard {
            iconName: "network-wireless-hotspot-symbolic"
            title: qsTr("Hotspot")
            description: !section.canHotspot ? qsTr("This Wi-Fi adapter cannot be a hotspot")
                       : !NetworkControl.canHotspot ? qsTr("The system policy does not allow a hotspot")
                       : qsTr("Share this computer's internet with other devices")
            clickable: section.canHotspot && NetworkControl.canHotspot && !section.hotspot
            enabled: section.canHotspot && NetworkControl.canHotspot
            onClicked: section.hotspotRequested(section.deviceId)
        }
    }

    HotspotActive {
        visible: section.wifi.enabled && section.hotspot
        deviceId: section.deviceId
        uuid: section.activeConnectionUuid
    }

    EmptyState {
        visible: !section.wifi.enabled && section.wifi.hardwareEnabled
        iconName: "network-wireless-disconnected-symbolic"
        title: qsTr("Wi-Fi is off")
        description: qsTr("Turn on Wi-Fi to see the networks in reach.")
        actionText: section.wifi.canToggle ? qsTr("Turn on Wi-Fi") : ""
        onActionClicked: section.wifi.setEnabled(true)
    }

    SettingsGroup {
        visible: section.wifi.enabled && !section.hotspot
        title: qsTr("Networks in reach")

        headerExtra: ProgressRing {
            visible: section.scanning
            width: 16
            height: 16
            thickness: 2
            value: 0.25
            Accessible.name: qsTr("Searching for networks")
            RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: section.scanning }
        }

        Repeater {
            model: WifiNetworksModel { id: networks; deviceId: section.deviceId }

            NetworkRow {
                onActivated: {
                    if (enterprise && !known) {
                        section.enterpriseRequested(deviceId, name, security)
                        return
                    }
                    if (active) {
                        section.detailsRequested(connectionUuid, deviceId, networkId)
                        return
                    }
                    networks.connectNetwork(networkId, result => {
                        if (!result.ok && result.error !== Network.ErrorCode.NotAllowed)
                            SettingsApp.toast(qsTr("Could not connect to %1").arg(name))
                    })
                }
                onShareClicked: section.shareRequested(connectionUuid)
                onDetailsClicked: section.detailsRequested(connectionUuid, deviceId, networkId)
            }
        }

        LText {
            visible: networks.count === 0
            text: qsTr("Searching for networks…")
            color: Theme.textSecondary
            Layout.topMargin: Theme.spacingS
        }
    }
}
