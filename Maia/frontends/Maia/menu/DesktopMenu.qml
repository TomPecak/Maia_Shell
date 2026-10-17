import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

// Context menu of the desktop in the style of iPadOS, opened by a right click on the wallpaper.
//
// Layer-shell surfaces cannot be placed at an arbitrary position from QML, so the menu lives
// in a transparent window covering the whole screen, above the other layers. The window is
// shown only while the menu is open: a click outside the menu closes it, a right click moves
// it to the new position, Escape or the loss of the keyboard focus close it too.
//
// The rows are mock-ups, except "Change Frontend": it opens a submenu over the menu
// (like the nested menus of iPadOS) with the frontends of Maia Shell.
Window {
    id: window

    property bool open: false
    // Position of the right click, in the coordinates of the screen
    property point position: Qt.point(0, 0)
    // Wallpaper of the desktop, the menu is made of frosted glass over it
    property url wallpaperSource

    readonly property int screenMargin: 12

    // Opens the menu at the given position (also moves an already open menu)
    function popup(x, y) {
        position = Qt.point(x, y)
        submenuOpen = false
        if (open)
            mainMenu.replay()
        open = true
    }

    function close() {
        open = false
    }

    property bool submenuOpen: false

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: open || mainMenu.visible

    LayerShell.Window.scope: "maia-desktop-menu"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    onOpenChanged: {
        d.hadFocus = false
        submenuOpen = false
    }

    // Close when the window loses the keyboard focus, e.g. after a global shortcut
    onActiveChanged: {
        if (active) {
            d.hadFocus = true
        } else if (d.hadFocus && open) {
            d.hadFocus = false
            close()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: window.open
        onActivated: {
            if (window.submenuOpen)
                window.submenuOpen = false
            else
                window.close()
        }
    }

    MFrontendModel {
        id: frontends
    }

    // Source of the frosted glass: the same wallpaper as on the desktop, at a lower
    // resolution (it is blurred anyway)
    Image {
        id: wallpaper

        anchors.fill: parent
        visible: false
        source: window.wallpaperSource
        sourceSize: Qt.size(Math.ceil(window.width / 2), Math.ceil(window.height / 2))
        asynchronous: true
    }

    // Outside of the menus: a click closes the menu, a right click moves it
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: mouse => {
            if (mouse.button !== Qt.RightButton)
                window.close()
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                window.popup(mouse.x, mouse.y)
        }
    }

    MenuPanel {
        id: mainMenu

        readonly property bool openLeft: window.position.x + width > window.width - window.screenMargin
        readonly property bool openUp: window.position.y + height > window.height - window.screenMargin

        open: window.open
        pushedBack: window.submenuOpen
        backdropSource: wallpaper.status === Image.Ready ? wallpaper : null
        x: openLeft ? Math.max(window.screenMargin, window.position.x - width) : window.position.x
        y: openUp ? Math.max(window.screenMargin, window.position.y - height) : window.position.y
        // Grows out of the corner at the click point
        originX: openLeft ? width : 0
        originY: openUp ? height : 0

        MenuItem {
            text: qsTr("New Folder")
            iconName: "folder-new-symbolic"
            enabled: false
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Paste")
            iconName: "edit-paste-symbolic"
            enabled: false
        }

        MenuSeparator { group: true }

        MenuItem {
            text: qsTr("Sort By")
            hasSubmenu: true
            enabled: false
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Show View Options")
            iconName: "view-grid-symbolic"
            enabled: false
        }

        MenuSeparator { group: true }

        MenuItem {
            text: qsTr("Change Wallpaper…")
            iconName: "view-preview-symbolic"
            enabled: false
        }

        MenuSeparator { group: true }

        MenuItem {
            id: frontendItem

            text: qsTr("Change Frontend")
            hasSubmenu: true
            onClicked: window.submenuOpen = true
        }
    }

    // Submenu over the main menu, it starts at the row which opened it
    MenuPanel {
        id: frontendMenu

        open: window.open && window.submenuOpen
        backdropSource: mainMenu.backdropSource
        closedScale: 0.92
        x: mainMenu.x + (mainMenu.width - width) / 2
        y: Math.max(window.screenMargin,
                    Math.min(mainMenu.y + frontendItem.y, window.height - window.screenMargin - height))
        originX: width / 2
        originY: 0

        // Header: closes the submenu
        MenuItem {
            text: frontendItem.text
            header: true
            onClicked: window.submenuOpen = false
        }

        MenuSeparator { group: true }

        Repeater {
            id: frontendRepeater

            model: frontends

            delegate: Column {
                id: frontendRow

                required property int index
                required property string frontendId
                required property string frontendName
                required property bool frontendActive

                width: parent ? parent.width : 0

                MenuSeparator {
                    visible: frontendRow.index > 0
                }

                MenuItem {
                    text: frontendRow.frontendName
                    checkColumn: true
                    checked: frontendRow.frontendActive
                    Accessible.checked: frontendRow.frontendActive

                    onClicked: {
                        window.close()
                        if (!frontendRow.frontendActive)
                            frontends.setActiveFrontend(frontendRow.frontendId)
                    }
                }
            }
        }

        MenuItem {
            visible: frontendRepeater.count === 0
            text: qsTr("No Frontends Found")
            enabled: false
        }
    }

    QtObject {
        id: d

        property bool hadFocus: false
    }
}
