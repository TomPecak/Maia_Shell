pragma Singleton

import QtQuick

import Maia.Network as Network

// Shared state of the Lumen shell: which flyout is open, the current time, the user
// and the actions triggered from the UI. All windows of the frontend run in one process,
// so they share this object directly.
QtObject {
    id: shell

    // --- Flyouts ---

    // Name of the open flyout: "start", "calendar", "quickSettings", "widgets" or "" (none)
    property string activeFlyout: ""

    function toggleFlyout(name) {
        closeDesktopMenu()
        activeFlyout = activeFlyout === name ? "" : name
    }

    function closeFlyouts() {
        activeFlyout = ""
    }

    // --- Desktop context menu ---

    property bool desktopMenuOpen: false
    // Position of the right click, in the coordinates of the screen
    property point desktopMenuPosition: Qt.point(0, 0)

    // Emitted on every request, also when the menu is already open (it moves to the new position)
    signal desktopMenuRequested()

    // Opens the menu at the given position, closes the open flyout
    function openDesktopMenu(x, y) {
        closeFlyouts()
        desktopMenuPosition = Qt.point(x, y)
        desktopMenuOpen = true
        desktopMenuRequested()
    }

    function closeDesktopMenu() {
        desktopMenuOpen = false
    }

    // --- Time ---

    property date now: new Date()

    property Timer clockTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.now = new Date()
    }

    // Greeting for the current part of the day
    readonly property string greeting: {
        const hour = now.getHours()
        if (hour < 5)
            return qsTr("Good night")
        if (hour < 12)
            return qsTr("Good morning")
        if (hour < 18)
            return qsTr("Good afternoon")
        return qsTr("Good evening")
    }

    // --- User ---

    // User name taken from the home directory (HOME is set by the Maia backend)
    readonly property string userName: {
        const home = typeof HOME !== "undefined" ? String(HOME) : ""
        const name = home.split("/").filter(part => part.length > 0).pop()
        return name ? name.charAt(0).toUpperCase() + name.slice(1) : qsTr("User")
    }
    readonly property string userInitials: userName.slice(0, 1)

    // --- Applications ---

    // Starts an application through the Maia backend and closes the open flyout.
    // "lumen:files" is the built-in File Explorer of Lumen (apps/files).
    function launch(exec) {
        if (exec === "lumen:files")
            openFileExplorer()
        else if (exec && typeof backend !== "undefined" && backend)
            backend.runCommand(exec)
        closeFlyouts()
    }

    // --- File Explorer (built-in application window) ---

    // The window exists while it is open (created by Main.qml)
    property bool fileExplorerOpen: false

    // Asks the open window to come to the front (or to minimize when it is active)
    signal fileExplorerActivationRequested()

    function openFileExplorer() {
        if (fileExplorerOpen)
            fileExplorerActivationRequested()
        else
            fileExplorerOpen = true
    }

    // --- Session and power ---

    // Maia's session manager (MSessionManager of Maia.Backend), set by shell/Main.qml. This module
    // is imported by app faces too (Maia Settings), in processes without the shell's backend, and
    // QML loads every singleton of an imported module: Shell must not import Maia.Backend itself.
    property var session: null

    // Which power actions the system offers (systemd-logind); the power menu shows only these
    readonly property bool canSuspend: session ? session.canSuspend : false
    readonly property bool canReboot: session ? session.canReboot : false
    readonly property bool canPowerOff: session ? session.canPowerOff : false

    // action: "logout", "suspend", "reboot" or "shutdown". Maia carries it out (MSessionManager);
    // in a nested development session the power actions are only logged, logind would act on the
    // real machine.
    function powerAction(action) {
        closeFlyouts()
        if (!session)
            console.warn("[Lumen] no session manager for", action)
        switch (action) {
        case "logout":
            if (session) session.logout()
            break
        case "suspend":
            if (session) session.suspend()
            break
        case "reboot":
            if (session) session.reboot()
            break
        case "shutdown":
            if (session) session.poweroff()
            break
        default:
            console.warn("[Lumen] unknown power action:", action)
        }
    }

    // --- Wi-Fi (the Maia network service) ---

    // One for the whole shell: the tile, the tray icon and the network list read it
    readonly property Network.WifiStatus wifi: Network.WifiStatus {}

    // Password requests of NetworkManager: Lumen asks inline, in the network list of quick
    // settings (as Windows 11). A request that comes while quick settings are closed (e.g. a saved
    // password was refused) opens them on the Wi-Fi page.
    readonly property Network.SecretPrompt wifiPrompt: Network.SecretPrompt {
        active: true
        onPendingChanged: {
            if (pending) {
                shell.quickSettingsPage = "wifi"
                if (shell.activeFlyout !== "quickSettings")
                    shell.toggleFlyout("quickSettings")
            }
        }
    }

    // The page quick settings show: "main" or "wifi" (back to main when they close)
    property string quickSettingsPage: "main"

    onActiveFlyoutChanged: {
        if (activeFlyout !== "quickSettings" && !wifiPrompt.pending)
            quickSettingsPage = "main"
    }

    // The tray icon of Wi-Fi: off, connecting, hotspot, or the signal of the connected network
    readonly property string wifiIconName: {
        if (!wifi.available || !wifi.enabled || !wifi.hasDevice)
            return "network-wireless-disconnected-symbolic"
        if (wifi.connecting)
            return "network-wireless-acquiring-symbolic"
        if (wifi.hotspot)
            return "network-wireless-hotspot-symbolic"
        if (!wifi.connected)
            return "network-wireless-signal-none-symbolic"
        return "network-wireless-signal-" + ["none", "weak", "ok", "good", "excellent"][wifi.signalLevel] + "-symbolic"
    }

    // --- Quick settings (mock state, not connected to the system yet) ---
    property bool bluetoothEnabled: false
    property bool airplaneMode: false
    property bool nightLight: false
    property bool focusMode: false
    property real brightness: 0.8

    // --- Notifications (mock data) ---

    property ListModel notifications: ListModel {
        ListElement { app: "Discover"; icon: "plasmadiscover"; title: "Updates available"; body: "12 packages can be updated."; time: "10:24" }
        ListElement { app: "Calendar"; icon: "view-calendar-symbolic"; title: "Design review"; body: "Starts in 15 minutes, room 2.04"; time: "09:45" }
        ListElement { app: "Files"; icon: "system-file-manager"; title: "Copy finished"; body: "48 photos copied to Pictures."; time: "08:12" }
    }
}
