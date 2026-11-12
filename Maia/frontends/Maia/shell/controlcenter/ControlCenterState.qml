import QtQuick
import QtCore

import Maia.Network as Network
import Maia.Power
import MaiaFrontend

// What the Control Center shows and changes, in one place: the button in the dock strip and the
// panel read the same state.
//
// Real: Wi-Fi (the Maia network service, Maia.Network), the battery and the brightness (the Maia
// power service, Maia.Power), the volume (the audio backend of Maia), the light / dark mode (Theme).
// Mock-ups (no backend in Maia yet; they change only what is shown, like Lumen's quick settings):
// Bluetooth, airplane mode, night light. Each is one property below, to be replaced by its backend.
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

    // --- The battery and the screen (the power service) ---

    // A computer without a battery shows none
    readonly property bool hasBattery: Power.hasBattery
    readonly property int batteryLevel: Math.round(Power.batteryPercentage)
    readonly property bool batteryCharging: Power.charging
    // UPower's low level (its threshold, about 20 %) and below
    readonly property bool batteryLow: Power.warningLevel !== Power.NoWarning
    readonly property string batteryIcon: hasBattery
                                          ? batteryIconFor(Power.batteryPercentage, Power.charging,
                                                           Power.batteryState === Power.Full)
                                          : ""
    // 0..1 of the built-in screen; setBrightness changes it (dragging is fine: Maia.Power thins it out)
    readonly property bool hasBrightness: Power.brightnessAvailable
    readonly property real brightness: Power.brightness

    function setBrightness(value) {
        Power.brightness = value
    }

    // The shipped Breeze glyphs (assets/icons): battery-080-symbolic, battery-030-charging-symbolic, …
    function batteryIconFor(percentage, charging, full) {
        if (full)
            return icon("battery-full-charged-symbolic")
        const level = Math.max(0, Math.min(100, Math.round(percentage / 10) * 10))
        return icon("battery-" + ("00" + level).slice(-3) + (charging ? "-charging" : "") + "-symbolic")
    }

    // --- Mock-ups ---

    property bool bluetooth: true
    property bool airplaneMode: false
    property bool nightLight: false

    readonly property string bluetoothIcon: icon("network-bluetooth-symbolic")

    // --- The layout of the button in the dock strip (being tried out) ---

    // The layouts of ControlCenterButton, the default first, and the chosen one. Kept between
    // sessions by name (the [MaiaControlCenter] group of maia.conf), so a changed order never turns
    // a saved choice into another layout; an unknown name means the default.
    readonly property var buttonLayouts: ["grid", "column", "row", "analog"]
    readonly property var buttonLayoutNames: [qsTr("Grid"), qsTr("Column"), qsTr("Row"), qsTr("Analog")]
    readonly property int buttonLayoutIndex: Math.max(0, buttonLayouts.indexOf(settings.buttonLayout))
    readonly property string buttonLayout: buttonLayouts[buttonLayoutIndex]

    function setButtonLayout(index) {
        settings.buttonLayout = buttonLayouts[index]
        // Written at once, not only when the process ends: the shell may be stopped any time
        settings.sync()
    }

    property Settings settings: Settings {
        category: "MaiaControlCenter"

        property string buttonLayout: "grid"
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
