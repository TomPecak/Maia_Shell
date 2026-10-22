import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import LumenFrontend

// Context menu of the desktop, opened by a right click on the wallpaper.
//
// Layer-shell surfaces cannot be placed at an arbitrary position from QML (margins are not
// available), so the menu lives in a transparent window covering the whole screen, above
// the taskbar. The window exists only while the menu is open: a click outside the menu
// closes it, a right click moves it to the new position, Escape or the loss of the
// keyboard focus close it too.
//
// The items are mock-ups, except "Personalize" (opens quick settings) and "Change frontend"
// (switches the frontend of Maia Shell, like in the other frontends).
Window {
    id: window

    readonly property bool open: Shell.desktopMenuOpen
    // Distance kept from the screen edges and the taskbar
    readonly property int screenMargin: Theme.spacingS
    readonly property int bottomLimit: height - Theme.taskbarHeight - screenMargin

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: open || mainMenu.visible

    LayerShell.Window.scope: "lumen-desktop-menu"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // Same coordinates as the desktop, the taskbar area included
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    onOpenChanged: {
        d.hadFocus = false
        d.closeSubmenu()
    }

    // Close when the window loses the keyboard focus, e.g. after a global shortcut
    onActiveChanged: {
        if (active) {
            d.hadFocus = true
        } else if (d.hadFocus && open) {
            d.hadFocus = false
            Shell.closeDesktopMenu()
        }
    }

    // Submenus open (and close) after the mouse rests on an item for a moment
    Connections {
        target: mainMenu

        function onHoveredItemChanged() {
            const item = mainMenu.hoveredItem
            if (item && item.hasSubmenu !== undefined) {
                d.hoveredItem = item
                submenuTimer.restart()
            }
        }
    }

    // Keeps the submenu open while the mouse is over it
    Connections {
        target: frontendMenu

        function onHoveredChanged() {
            if (frontendMenu.hovered) {
                d.hoveredItem = d.submenuItem
                submenuTimer.stop()
            }
        }
    }

    Connections {
        target: Shell

        function onDesktopMenuRequested() {
            d.closeSubmenu()
            mainMenu.replay()
        }
    }

    Shortcut {
        sequences: ["Escape", "Left"]
        enabled: window.open
        onActivated: {
            if (d.submenuItem)
                d.closeSubmenu()
            else
                Shell.closeDesktopMenu()
        }
    }

    Maia.MFrontendModel {
        id: frontends
    }

    // Outside of the menus: a click closes the menu, a right click moves it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: mouse => {
            if (mouse.button !== Qt.RightButton)
                Shell.closeDesktopMenu()
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                Shell.openDesktopMenu(mouse.x, mouse.y)
        }
    }

    LMenu {
        id: mainMenu

        readonly property point position: Shell.desktopMenuPosition

        open: window.open
        openUpwards: position.y + height > window.bottomLimit
        x: Math.max(window.screenMargin, Math.min(position.x, window.width - width - window.screenMargin))
        y: openUpwards ? Math.max(window.screenMargin, position.y - height) : position.y

        LMenuItem {
            text: qsTr("View")
            iconName: "view-grid-symbolic"
            hasSubmenu: true
            enabled: false
        }
        LMenuItem {
            text: qsTr("Sort by")
            iconName: "view-sort-symbolic"
            hasSubmenu: true
            enabled: false
        }
        LMenuItem {
            text: qsTr("Refresh")
            iconName: "view-refresh-symbolic"
            enabled: false
        }

        LMenuSeparator {}

        LMenuItem {
            text: qsTr("New")
            iconName: "document-new-symbolic"
            hasSubmenu: true
            enabled: false
        }

        LMenuSeparator {}

        LMenuItem {
            text: qsTr("Display settings")
            iconName: "preferences-desktop-display-randr-symbolic"
            enabled: false
        }
        LMenuItem {
            text: qsTr("Personalize")
            iconName: "draw-brush-symbolic"
            onClicked: Shell.toggleFlyout("quickSettings")
        }

        LMenuSeparator {}

        LMenuItem {
            id: frontendItem

            text: qsTr("Change frontend")
            iconName: "window-duplicate-symbolic"
            hasSubmenu: true
            highlighted: d.submenuItem === this
            onClicked: d.openSubmenu(this)
        }

        LMenuSeparator {}

        LMenuItem {
            text: qsTr("Open in Terminal")
            iconName: "utilities-terminal-symbolic"
            enabled: false
        }
    }

    // Frontends of Maia Shell, the active one is checked
    LMenu {
        id: frontendMenu

        open: window.open && d.submenuItem === frontendItem
        implicitWidth: 220
        x: mainMenu.x + mainMenu.width + width <= window.width - window.screenMargin
           ? mainMenu.x + mainMenu.width - Theme.spacingXS
           : mainMenu.x - width + Theme.spacingXS
        y: Math.max(window.screenMargin,
                    Math.min(mainMenu.y + frontendItem.y, window.bottomLimit - height))

        Repeater {
            id: frontendRepeater

            model: frontends

            delegate: LMenuItem {
                required property string frontendId
                required property string frontendName
                required property bool frontendActive

                text: frontendName
                iconName: frontendActive ? "checkmark-symbolic" : ""
                iconColor: Theme.accent
                Accessible.checked: frontendActive

                onClicked: {
                    Shell.closeDesktopMenu()
                    if (!frontendActive)
                        frontends.setActiveFrontend(frontendId)
                }
            }
        }

        LMenuItem {
            visible: frontendRepeater.count === 0
            text: qsTr("No frontends found")
            enabled: false
        }
    }

    QtObject {
        id: d

        property bool hadFocus: false
        // Item whose submenu is open
        property Item submenuItem: null
        // Last item under the mouse, its submenu opens (or the open one closes) after a delay
        property Item hoveredItem: null

        function openSubmenu(item) {
            submenuTimer.stop()
            submenuItem = item
        }

        function closeSubmenu() {
            submenuTimer.stop()
            submenuItem = null
            hoveredItem = null
        }
    }

    Timer {
        id: submenuTimer

        interval: 300
        onTriggered: d.submenuItem = d.hoveredItem && d.hoveredItem.enabled && d.hoveredItem.hasSubmenu
                                     ? d.hoveredItem : null
    }
}
