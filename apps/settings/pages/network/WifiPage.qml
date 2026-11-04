import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

import "Texts.js" as Texts

// Settings › Wi-Fi (docs/gnome-wifi-features.md, section 3): the switch and state, saved networks,
// a hidden network, the hotspot, and the networks in reach. With several adapters a selector bar
// switches between them; each has its own list and state.
SettingsPage {
    id: page

    title: qsTr("Wi-Fi")

    WifiStatus {
        id: wifiStatus

        onActivationFailed: (name, reason) => {
            failure.title = name.length > 0 ? qsTr("Could not connect to “%1”").arg(name) : qsTr("Could not connect")
            failure.message = Texts.reason(reason)
            failure.visible = true
        }
        onConnectedTo: failure.visible = false
    }

    WifiDevicesModel { id: devices }

    // GNOME scans every 15 s while the panel is open, so the list stays fresh
    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: page.visible && wifiStatus.enabled && wifiStatus.hasDevice
        onTriggered: wifiStatus.scan()
    }

    // The adapter shown ("" until the model has one)
    property int deviceIndex: 0

    // --- Wi-Fi unavailable, no adapter: the page has nothing else to show ---

    EmptyState {
        visible: !wifiStatus.available
        iconName: "network-wireless-disconnected-symbolic"
        title: qsTr("Wi-Fi unavailable")
        description: qsTr("The network service or NetworkManager is not running.")
    }

    EmptyState {
        visible: wifiStatus.available && !wifiStatus.hasDevice
        iconName: "network-wireless-disconnected-symbolic"
        title: qsTr("No Wi-Fi adapter found")
        description: wifiStatus.hardwareEnabled ? qsTr("Make sure a Wi-Fi adapter is plugged in and turned on.")
                                          : qsTr("A hardware switch turns Wi-Fi off.")
    }

    SelectorBar {
        visible: wifiStatus.available && devices.count > 1
        model: {
            const names = []
            for (let i = 0; i < devices.count; ++i)
                names.push(devices.data(devices.index(i, 0), WifiDevicesModel.DeviceIdRole))
            return names
        }
        currentIndex: page.deviceIndex
        onCurrentIndexChanged: page.deviceIndex = currentIndex
    }

    InfoBar {
        id: failure

        visible: false
        severity: "error"
        closable: true
        onCloseClicked: visible = false
    }

    Repeater {
        model: wifiStatus.available ? devices : null

        DeviceSection {
            required property int index

            visible: index === page.deviceIndex
            wifi: wifiStatus
            Layout.fillWidth: true
            onHiddenRequested: deviceId => page.openHidden(deviceId)
            onHotspotRequested: deviceId => page.openHotspot(deviceId)
            onEnterpriseRequested: (deviceId, ssid, security) => page.openEnterprise(deviceId, ssid, security)
            onShareRequested: uuid => page.share(uuid)
            onDetailsRequested: (uuid, deviceId, networkId) => page.details(uuid, deviceId, networkId)
        }
    }

    Item { Layout.preferredHeight: Theme.spacingXL }

    // --- Testing: open a dialog at start (maia-settings --page network --action hidden) ---

    // After the state arrived from the service
    Timer {
        running: SettingsApp.testAction.length > 0
        interval: 800
        onTriggered: {
            const action = SettingsApp.testAction
            SettingsApp.testAction = ""
            const device = devices.count > 0 ? devices.get(devices.data(devices.index(0, 0), WifiDevicesModel.DeviceIdRole)) : ({})
            if (action === "hidden")
                page.openHidden(device.deviceId || "")
            else if (action === "enterprise")
                page.openEnterprise(device.deviceId || "", "Office", Network.Security.WpaEnterprise)
            else if (action === "hotspot")
                page.openHotspot(device.deviceId || "")
            else if (action === "hotspot-on")
                NetworkControl.startHotspot(device.deviceId || "", "", "")
            else if (action === "saved" || action === "forget")
                SettingsApp.push(Qt.resolvedUrl("SavedNetworksPage.qml"), { testForget: action === "forget" })
            else if (action === "share")
                page.share(device.activeConnectionUuid)
            else if (action.startsWith("details"))
                SettingsApp.push(Qt.resolvedUrl("NetworkDetailsPage.qml"), { uuid: device.activeConnectionUuid, deviceId: device.deviceId,
                                                                            networkId: device.activeNetworkId, initialTab: parseInt(action.split(":")[1] || "0") })
        }
    }

    HiddenNetworkDialog { id: hiddenDialog }
    HotspotDialog { id: hotspotDialog }
    ShareDialog { id: shareDialog }

    // For the sections and rows
    function openHidden(deviceId) {
        hiddenDialog.openNew(deviceId, "", Network.Security.WpaPersonal, true)
    }

    function openEnterprise(deviceId, ssid, security) {
        hiddenDialog.openNew(deviceId, ssid, security, false)
    }

    function openHotspot(deviceId) {
        hotspotDialog.openFor(deviceId)
    }

    function share(uuid) {
        shareDialog.openFor(uuid)
    }

    function details(uuid, deviceId, networkId) {
        SettingsApp.push(Qt.resolvedUrl("NetworkDetailsPage.qml"), { uuid: uuid, deviceId: deviceId, networkId: networkId })
    }
}
