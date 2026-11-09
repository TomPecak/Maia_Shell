import QtQuick
import QtCore

import Maia.Network as Network
import MaiaFrontend

// What the Control Center shows and changes, in one place: the button in the dock strip and the
// panel read the same state.
//
// Real: Wi-Fi (the Maia network service, Maia.Network), the volume (the audio backend of Maia),
// the light / dark mode (Theme).
// Mock-ups (no backend in Maia yet; they change only what is shown, like Lumen's quick settings):
// Bluetooth, airplane mode, night light, focus, brightness, battery. Each is one property below,
// to be replaced by its backend.
QtObject {
    id: state

    // --- Wi-Fi ---

    readonly property Network.WifiStatus wifi: Network.WifiStatus {}

    // Password requests of NetworkManager: the Maia frontend answers them in the network list of
    // the Control Center (the session has one prompter, the active frontend's)
    readonly property Network.SecretPrompt wifiPrompt: Network.SecretPrompt {
        active: true
    }

    readonly property string wifiIcon: {
        if (!wifi.available || !wifi.enabled || !wifi.hasDevice)
            return icon("network-wireless-disconnected-symbolic")
        if (wifi.connecting)
            return icon("network-wireless-acquiring-symbolic")
        if (wifi.hotspot)
            return icon("network-wireless-hotspot-symbolic")
        if (!wifi.connected)
            return icon("network-wireless-signal-none-symbolic")
        return signalIcon(wifi.signalLevel)
    }

    // A short state for the Wi-Fi toggle: the network, or why there is none
    readonly property string wifiText: !wifi.available ? qsTr("Unavailable")
                                     : !wifi.hasDevice ? qsTr("No adapter")
                                     : !wifi.enabled ? qsTr("Off")
                                     : wifi.hotspot ? qsTr("Hotspot")
                                     : wifi.connecting ? qsTr("Connecting…")
                                     : wifi.connected ? wifi.networkName
                                     : qsTr("Not connected")

    function signalIcon(level) {
        return icon("network-wireless-signal-" + ["none", "weak", "ok", "good", "excellent"][Math.max(0, Math.min(4, level))]
                    + "-symbolic")
    }

    // --- Volume ---

    readonly property bool hasAudio: typeof audioBackend !== "undefined" && audioBackend !== null
    readonly property bool muted: hasAudio && audioBackend.prefferedOutputMuted
    // 0..1 of the normal volume (100 %)
    readonly property real volume: hasAudio && audioBackend.normalVolume > 0
                                   ? Math.min(1, audioBackend.prefferedOutputVolume / audioBackend.normalVolume) : 0

    function setVolume(value) {
        if (!hasAudio)
            return
        audioBackend.prefferedOutputVolume = Math.round(Math.max(0, Math.min(1, value)) * audioBackend.normalVolume)
        if (value > 0 && muted)
            audioBackend.prefferedOutputMuted = false
    }

    function toggleMuted() {
        if (hasAudio)
            audioBackend.prefferedOutputMuted = !audioBackend.prefferedOutputMuted
    }

    readonly property string volumeIcon: muted || volume === 0 ? icon("audio-volume-muted-symbolic")
                                       : volume < 0.34 ? icon("audio-volume-low-symbolic")
                                       : volume < 0.67 ? icon("audio-volume-medium-symbolic")
                                       : icon("audio-volume-high-symbolic")

    // --- Mock-ups ---

    property bool bluetooth: true
    property bool airplaneMode: false
    property bool nightLight: false
    property bool focus: false
    // 0..1
    property real brightness: 0.7
    // Percent, and whether the charger is plugged in
    property int batteryLevel: 80
    property bool batteryCharging: false

    readonly property string batteryIcon: batteryCharging ? icon("battery-full-charging-symbolic")
                                                          : icon("battery-080-symbolic")
    readonly property string bluetoothIcon: icon("network-bluetooth-symbolic")

    // --- The layout of the button in the dock strip (being tried out) ---

    // ControlCenterButton.layout; kept between sessions (the [MaiaControlCenter] group of maia.conf)
    readonly property int buttonLayout: settings.buttonLayout

    function setButtonLayout(layout) {
        settings.buttonLayout = layout
    }

    property Settings settings: Settings {
        category: "MaiaControlCenter"

        property int buttonLayout: 0
    }

    // --- Helpers ---

    // An icon shipped with the frontend (assets/icons/README.md)
    function icon(name) {
        return Qt.resolvedUrl("../../assets/icons/" + name + ".svg")
    }

    // Starts a program of the session (Maia Settings and the like)
    function launch(command) {
        if (typeof backend !== "undefined" && backend)
            backend.runCommand(command)
    }
}
