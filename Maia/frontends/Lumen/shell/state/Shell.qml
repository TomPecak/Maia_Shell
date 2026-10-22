pragma Singleton

import QtQuick

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

    // Applications pinned to the taskbar
    readonly property var taskbarApps: [
        { name: qsTr("Files"), icon: "system-file-manager", exec: "lumen:files", running: false },
        { name: qsTr("Firefox"), icon: "firefox", exec: "firefox", running: true },
        { name: qsTr("Terminal"), icon: "utilities-terminal", exec: "konsole", running: false },
        { name: qsTr("Kate"), icon: "kate", exec: "kate", running: false },
        { name: qsTr("Discover"), icon: "plasmadiscover", exec: "plasma-discover", running: false },
        { name: qsTr("Settings"), icon: "systemsettings", exec: "systemsettings", running: false }
    ]

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
    property bool fileExplorerActive: false

    // Asks the open window to come to the front (or to minimize when it is active)
    signal fileExplorerActivationRequested()

    function openFileExplorer() {
        if (fileExplorerOpen)
            fileExplorerActivationRequested()
        else
            fileExplorerOpen = true
    }

    // TODO: Power actions are not connected to the session manager yet. In a nested
    // development session they would act on the host system (e.g. restart the real machine).
    function powerAction(action) {
        console.log("[Lumen] power action not implemented:", action)
        closeFlyouts()
    }

    // --- Quick settings (mock state, not connected to the system yet) ---

    property bool wifiEnabled: true
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
