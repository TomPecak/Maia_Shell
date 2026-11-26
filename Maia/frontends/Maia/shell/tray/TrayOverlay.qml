pragma ComponentBehavior: Bound

import QtQuick

import Maia.Tray
import MaiaFrontend

import "../menu"

// What the tray opens, above the dock: the panel with all items ("+N" on the plate) and the menu
// of an item. Both are menus of Maia (MenuPanel.qml, the desktop's menu): they grow out of the
// corner next to what opened them, beside the dock strip, and a click outside, Escape or the
// plate closes them. A menu opened from the panel lies over it (the panel steps back); a submenu
// lies over its menu and starts at the row that opened it, its title leads back.
//
// The menu opens once the application has sent it (ready), so it never grows in front of the
// user; an application that does not answer within a moment gets a menu that says so.
//
// Fills the whole window; the parent gives it the window's input region while it is open.
Item {
    id: overlay

    // Every item, for the panel (roles of Maia.Tray's TrayItemsModel)
    property var allItems: null
    property bool panelOpen: false
    // The item whose menu is open (0: none), and what opened it
    property int menuItemId: 0
    property Item menuAnchor: null
    // What the panel grows out of: the plate
    property Item plate: null
    property int dockEdge: Qt.BottomEdge
    property real dockStrip: 0

    readonly property bool open: panelOpen || menuItemId !== 0

    signal closeRequested()
    // The menu alone closes (picked, its item gone, Escape)
    signal menuCloseRequested()
    // The panel's icons
    signal activated(int itemId, Item icon)
    signal secondaryActivated(int itemId, Item icon)
    signal menuRequested(int itemId, Item icon)
    signal contextMenuRequested(int itemId, Item icon)
    signal scrolled(int itemId, int delta, bool horizontal)
    // Closed: the window that had the keyboard before should get it back
    signal dismissed()

    // From the panels' own flags: their visible is false while this item is hidden (a deadlock)
    visible: panel.shown || menuPanel.shown || submenuPanel.shown

    onOpenChanged: {
        if (open) {
            if (Window.window)
                Window.window.requestActivate()
            keyHandler.forceActiveFocus()
        } else {
            dismissed()
        }
    }

    onPanelOpenChanged: {
        if (panelOpen)
            d.panelRect = d.rectOf(plate)
    }

    onMenuItemIdChanged: {
        d.levels = []
        d.waited = false
        if (menuItemId === 0)
            return
        d.menuOverPanel = panelOpen
        d.menuRect = d.rectOf(menuAnchor)
        waitTimer.restart()
    }

    // --- Outside of what is open ---

    MouseArea {
        anchors.fill: parent
        visible: overlay.open
        acceptedButtons: Qt.AllButtons
        onPressed: overlay.closeRequested()
        onWheel: wheel => { wheel.accepted = true }
    }

    Item {
        id: keyHandler

        focus: true

        Keys.onEscapePressed: {
            if (d.levels.length > 0)
                d.back()
            else if (overlay.menuItemId !== 0 && overlay.panelOpen)
                overlay.menuCloseRequested()
            else
                overlay.closeRequested()
        }
    }

    // --- The panel: all items ---

    MenuPanel {
        id: panel

        readonly property int columns: Math.max(1, Math.min(4, overlay.allItems ? overlay.allItems.count : 1))

        objectName: "trayPanel"
        open: overlay.panelOpen
        pushedBack: menuPanel.open && d.menuOverPanel
        width: columns * d.cell + 2 * 10
        implicitHeight: grid.implicitHeight + 2 * 10
        x: d.place(d.panelRect, width, height).x
        y: d.place(d.panelRect, width, height).y
        transformOrigin: d.origin

        Grid {
            id: grid

            x: 10
            columns: panel.columns

            Repeater {
                model: overlay.allItems

                delegate: Item {
                    id: cell

                    required property int itemId
                    required property string currentIconSource
                    required property bool currentIconIsMask
                    required property string overlayIconSource
                    required property bool needsAttention
                    required property bool hasMenu
                    required property bool itemIsMenu
                    required property string title
                    required property string appName

                    width: d.cell
                    height: d.cell + 6

                    TrayIcon {
                        id: icon

                        objectName: "trayPanelIcon"
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 6
                        width: 48
                        height: 48
                        iconSize: 32
                        source: cell.currentIconSource
                        isMask: cell.currentIconIsMask
                        overlaySource: cell.overlayIconSource
                        needsAttention: cell.needsAttention
                        hasMenu: cell.hasMenu
                        itemIsMenu: cell.itemIsMenu
                        name: label.text
                        checked: overlay.menuItemId === cell.itemId

                        onActivated: overlay.activated(cell.itemId, icon)
                        onSecondaryActivated: overlay.secondaryActivated(cell.itemId, icon)
                        onMenuRequested: overlay.menuRequested(cell.itemId, icon)
                        onContextMenuRequested: overlay.contextMenuRequested(cell.itemId, icon)
                        onScrolled: (delta, horizontal) => overlay.scrolled(cell.itemId, delta, horizontal)
                    }

                    Text {
                        id: label

                        anchors.top: icon.bottom
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 6
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.appName !== "" ? cell.appName : cell.title
                        color: "black"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // --- The menu of an item ---

    TrayMenu {
        id: trayMenu

        itemId: overlay.menuItemId
        active: overlay.menuItemId !== 0
        onClosed: overlay.menuCloseRequested()
    }

    // An application that is slow to send its menu: the menu opens anyway after a moment
    Timer {
        id: waitTimer

        interval: 600
        onTriggered: d.waited = true
    }

    MenuPanel {
        id: menuPanel

        objectName: "trayMenu"
        open: overlay.menuItemId !== 0 && (trayMenu.ready || d.waited)
        pushedBack: submenuPanel.open
        x: d.menuOverPanel ? panel.x + (panel.width - width) / 2 : d.place(d.menuRect, width, height).x
        y: d.menuOverPanel ? Math.min(panel.y, overlay.height - d.margin - height) : d.place(d.menuRect, width, height).y
        closedScale: d.menuOverPanel ? 0.92 : 0.5
        transformOrigin: d.menuOverPanel ? Item.Top : d.origin

        MenuLevel {
            model: trayMenu.entries
            onEntryOpened: (entryId, label, row) => d.push(entryId, label, row)
        }

        MenuItem {
            visible: trayMenu.entries.count === 0
            text: trayMenu.ready ? qsTr("Nothing to show") : qsTr("Not answering")
            enabled: false
        }
    }

    // A submenu over the menu
    MenuPanel {
        id: submenuPanel

        readonly property var level: d.levels.length > 0 ? d.levels[d.levels.length - 1] : null

        objectName: "traySubmenu"
        open: menuPanel.open && level !== null
        closedScale: 0.92
        x: menuPanel.x + (menuPanel.width - width) / 2
        y: Math.max(d.margin, Math.min(level ? level.y : menuPanel.y, overlay.height - d.margin - height))
        transformOrigin: Item.Top

        // Its title: back to the level above
        MenuItem {
            text: submenuPanel.level ? submenuPanel.level.label : ""
            header: true
            onClicked: d.back()
        }

        MenuSeparator { group: true }

        MenuLevel {
            model: submenuPanel.level ? trayMenu.submenu(submenuPanel.level.entryId) : null
            onEntryOpened: (entryId, label, row) => d.push(entryId, label, row)
        }
    }

    // The entries of one level of a menu
    component MenuLevel: Column {
        id: level

        property var model: null

        signal entryOpened(int entryId, string label, Item row)

        width: parent ? parent.width : 0

        Repeater {
            model: level.model

            delegate: Column {
                id: entry

                required property int index
                required property bool groupStart
                required property int entryId
                required property bool separator
                required property string label
                required property bool enabled
                required property string iconSource
                required property bool iconIsMask
                required property int toggle
                required property bool checked
                required property bool submenu

                width: level.width

                MenuSeparator {
                    visible: entry.separator
                    group: true
                }

                // Between the rows of a group, as in the desktop's menu
                MenuSeparator {
                    visible: !entry.separator && !entry.groupStart
                }

                MenuItem {
                    id: row

                    objectName: "trayMenuEntry"
                    visible: !entry.separator
                    text: entry.label
                    enabled: entry.enabled
                    iconSource: entry.iconSource
                    iconIsMask: entry.iconIsMask
                    hasSubmenu: entry.submenu
                    checkColumn: level.model && level.model.hasToggles
                    checked: entry.toggle !== 0 && entry.checked
                    Accessible.checkable: entry.toggle !== 0
                    Accessible.checked: entry.checked

                    onClicked: {
                        if (entry.submenu)
                            level.entryOpened(entry.entryId, entry.label, row)
                        else
                            trayMenu.trigger(entry.entryId, overlay.Window.window)
                    }
                }
            }
        }
    }

    QtObject {
        id: d

        readonly property real gap: 12
        readonly property real margin: 12
        readonly property real cell: 84
        // The corner nearest to the plate
        readonly property int origin: overlay.dockEdge === Qt.LeftEdge ? Item.TopLeft
                                    : overlay.dockEdge === Qt.BottomEdge ? Item.BottomRight
                                    : Item.TopRight

        property rect panelRect: Qt.rect(0, 0, 0, 0)
        property rect menuRect: Qt.rect(0, 0, 0, 0)
        property bool menuOverPanel: false
        property bool waited: false
        // The open submenus: { entryId, label, y }
        property var levels: []

        function rectOf(item) {
            if (!item)
                return Qt.rect(overlay.width / 2, overlay.height / 2, 0, 0)
            const at = item.mapToItem(overlay, 0, 0)
            return Qt.rect(at.x, at.y, item.width, item.height)
        }

        // Beside the dock strip, next to `r` along it, inside the screen
        function place(r, width, height) {
            const clampX = x => Math.max(margin, Math.min(x, overlay.width - margin - width))
            const clampY = y => Math.max(margin, Math.min(y, overlay.height - margin - height))
            switch (overlay.dockEdge) {
            case Qt.LeftEdge:
                return Qt.point(overlay.dockStrip + gap, clampY(r.y))
            case Qt.RightEdge:
                return Qt.point(overlay.width - overlay.dockStrip - gap - width, clampY(r.y))
            case Qt.TopEdge:
                return Qt.point(clampX(r.x + r.width - width), overlay.dockStrip + gap)
            default:
                return Qt.point(clampX(r.x + r.width - width), overlay.height - overlay.dockStrip - gap - height)
            }
        }

        function push(entryId, label, row) {
            const at = row.mapToItem(overlay, 0, 0)
            trayMenu.aboutToShow(entryId)
            levels = levels.concat([{ entryId: entryId, label: label, y: at.y }])
            submenuPanel.replay()
        }

        function back() {
            if (levels.length === 0)
                return
            trayMenu.submenuClosed(levels[levels.length - 1].entryId)
            levels = levels.slice(0, levels.length - 1)
            if (levels.length > 0)
                submenuPanel.replay()
        }
    }
}
