pragma ComponentBehavior: Bound

import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Tray

import LumenFrontend

// What the system tray of the taskbar opens: the hidden icons ("^") and the menu of an item, as
// menus of Lumen (LMenu, the desktop's menu) above the taskbar, next to the button that opened
// them. Submenus open to the side when the mouse rests on their row (or at a click), like the
// desktop's.
//
// The menu opens once the application has sent it (ready), so it never grows in front of the
// user; an application that does not answer within a moment gets a menu that says so.
//
// Like the desktop menu, a transparent window over the whole screen, shown only while something is
// open: a click outside closes it, as do Escape and the loss of the keyboard focus.
Window {
    id: window

    readonly property bool open: Shell.trayOverflowOpen || Shell.trayMenuItemId !== 0
    readonly property int screenMargin: Theme.spacingS
    // Above the taskbar
    readonly property int bottomLimit: height - Theme.taskbarHeight - Theme.spacingS

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: open || overflow.visible || menu.visible || d.anySubmenuVisible

    LayerShell.Window.scope: "lumen-tray-popup"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    onOpenChanged: d.hadFocus = false

    // Close when the window loses the keyboard focus, e.g. after a global shortcut
    onActiveChanged: {
        if (active) {
            d.hadFocus = true
        } else if (d.hadFocus && open) {
            d.hadFocus = false
            Shell.closeTray()
        }
    }

    Connections {
        target: Shell

        function onTrayMenuItemIdChanged() {
            d.levels = []
            d.waited = false
            if (Shell.trayMenuItemId !== 0)
                waitTimer.restart()
        }
    }

    Shortcut {
        sequences: ["Escape", "Left"]
        enabled: window.open
        onActivated: {
            if (d.levels.length > 0)
                d.closeFrom(d.levels.length - 1)
            else if (Shell.trayMenuItemId !== 0 && Shell.trayOverflowOpen)
                Shell.trayMenuItemId = 0
            else
                Shell.closeTray()
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Shell.closeTray()
    }

    // --- The hidden icons ---

    TrayItemsModel {
        id: hiddenItems

        filter: TrayItemsModel.Passive
    }

    LMenu {
        id: overflow

        readonly property int columns: Math.max(1, Math.min(4, hiddenItems.count))

        open: Shell.trayOverflowOpen
        openUpwards: true
        implicitWidth: columns * 40 + 2 * Theme.spacingXS
        x: Math.max(window.screenMargin, Math.min(Shell.trayOverflowPosition.x - width / 2 - 16,
                                                  window.width - window.screenMargin - width))
        y: window.bottomLimit - height

        Grid {
            x: Theme.spacingXS
            columns: overflow.columns

            Repeater {
                model: hiddenItems

                delegate: Item {
                    id: hiddenItem

                    required property int itemId
                    required property string currentIconSource
                    required property string overlayIconSource
                    required property bool needsAttention
                    required property bool hasMenu
                    required property bool itemIsMenu
                    required property string title
                    required property string toolTipTitle
                    required property string toolTipText

                    width: 40
                    height: 40

                    TrayIconButton {
                        id: hiddenButton

                        objectName: "trayOverflowIcon"
                        anchors.fill: parent
                        iconSize: 20
                        source: hiddenItem.currentIconSource
                        overlaySource: hiddenItem.overlayIconSource
                        needsAttention: hiddenItem.needsAttention
                        hasMenu: hiddenItem.hasMenu
                        itemIsMenu: hiddenItem.itemIsMenu
                        highlighted: Shell.trayMenuItemId === hiddenItem.itemId
                        toolTip: [hiddenItem.toolTipTitle !== "" ? hiddenItem.toolTipTitle : hiddenItem.title, hiddenItem.toolTipText]
                                 .filter(t => t !== "").join("\n")
                        Accessible.name: hiddenItem.title

                        onActivated: {
                            Shell.closeTray()
                            Tray.activate(hiddenItem.itemId, 0, 0, window)
                        }
                        onSecondaryActivated: Tray.secondaryActivate(hiddenItem.itemId, 0, 0, window)
                        // The overflow stays open under the menu
                        onMenuRequested: {
                            const at = mapToItem(null, 0, 0)
                            Shell.openTrayMenu(hiddenItem.itemId, at.x, at.y)
                        }
                        onContextMenuRequested: {
                            Shell.closeTray()
                            Tray.contextMenu(hiddenItem.itemId, 0, 0)
                        }
                        onScrolled: (delta, horizontal) => Tray.scroll(hiddenItem.itemId, delta, horizontal)
                    }
                }
            }
        }
    }

    // --- The menu of an item ---

    TrayMenu {
        id: trayMenu

        itemId: Shell.trayMenuItemId
        active: Shell.trayMenuItemId !== 0
        onClosed: Shell.trayMenuItemId = 0
    }

    // An application that is slow to send its menu: the menu opens anyway after a moment
    Timer {
        id: waitTimer

        interval: 600
        onTriggered: d.waited = true
    }

    LMenu {
        id: menu

        open: Shell.trayMenuItemId !== 0 && (trayMenu.ready || d.waited)
        openUpwards: true
        x: Math.max(window.screenMargin, Math.min(Shell.trayMenuPosition.x, window.width - window.screenMargin - width))
        // Above the button that opened it (the overflow's or the taskbar's)
        y: Math.max(window.screenMargin, Math.min(Shell.trayMenuPosition.y - Theme.spacingS, window.bottomLimit) - height)

        MenuLevel {
            depth: 0
            model: trayMenu.entries
        }

        LMenuItem {
            visible: trayMenu.entries.count === 0
            text: trayMenu.ready ? qsTr("Nothing to show") : qsTr("Not answering")
            enabled: false
        }
    }

    // The open submenus, each to the side of the row that opened it
    Repeater {
        model: d.levels.length

        delegate: LMenu {
            id: submenu

            required property int index
            readonly property var level: d.levels[index] ?? null

            open: menu.open && level !== null
            implicitWidth: 240
            x: level ? (level.x + level.width + width <= window.width - window.screenMargin
                        ? level.x + level.width - Theme.spacingXS : level.x - width + Theme.spacingXS) : 0
            y: level ? Math.max(window.screenMargin, Math.min(level.y, window.bottomLimit - height)) : 0

            MenuLevel {
                depth: submenu.index + 1
                model: submenu.level ? trayMenu.submenu(submenu.level.entryId) : null
            }

            LMenuItem {
                visible: submenu.level !== null && trayMenu.submenu(submenu.level.entryId).count === 0
                text: qsTr("Empty")
                enabled: false
            }
        }
    }

    // The entries of one level of the menu
    component MenuLevel: Column {
        id: level

        property int depth: 0
        property var model: null

        width: parent ? parent.width : 0

        Repeater {
            model: level.model

            delegate: Column {
                id: entry

                required property int entryId
                required property bool separator
                required property string label
                required property bool enabled
                required property string iconSource
                required property int toggle
                required property bool checked
                required property string shortcut
                required property bool submenu

                width: level.width

                LMenuSeparator {
                    visible: entry.separator
                }

                LMenuItem {
                    id: row

                    visible: !entry.separator
                    text: entry.label
                    enabled: entry.enabled
                    shortcut: entry.shortcut
                    hasSubmenu: entry.submenu
                    // A check mark of a toggle that is on; else the application's icon
                    iconName: entry.toggle !== 0 && entry.checked ? "checkmark-symbolic" : ""
                    iconColor: Theme.accent
                    iconSource: entry.toggle !== 0 ? "" : entry.iconSource
                    highlighted: d.levels.length > level.depth && d.levels[level.depth].entryId === entry.entryId
                    Accessible.checkable: entry.toggle !== 0
                    Accessible.checked: entry.checked

                    onHoveredChanged: {
                        if (hovered)
                            d.hover(level.depth, entry.submenu && entry.enabled ? row : null, entry.entryId)
                    }
                    onClicked: {
                        if (entry.submenu)
                            d.openSubmenu(level.depth, row, entry.entryId)
                        else
                            trayMenu.trigger(entry.entryId, window)
                    }
                }
            }
        }
    }

    QtObject {
        id: d

        property bool hadFocus: false
        property bool waited: false
        // The open submenus: { entryId, x, y, width } of the row that opened each
        property var levels: []
        readonly property bool anySubmenuVisible: levels.length > 0
        // The row under the mouse, its submenu opens (or deeper ones close) after a moment
        property var pending: null

        function openSubmenu(depth, row, entryId) {
            hoverTimer.stop()
            const at = row.mapToItem(null, 0, 0)
            closeFrom(depth)
            trayMenu.aboutToShow(entryId)
            levels = levels.concat([{ entryId: entryId, x: at.x, y: at.y, width: row.width }])
        }

        // The submenus from `depth` on close
        function closeFrom(depth) {
            for (let i = levels.length - 1; i >= depth; --i)
                trayMenu.submenuClosed(levels[i].entryId)
            levels = levels.slice(0, depth)
        }

        function hover(depth, row, entryId) {
            if (levels.length > depth && levels[depth].entryId === entryId)
                return
            pending = { depth: depth, row: row, entryId: entryId }
            hoverTimer.restart()
        }
    }

    Timer {
        id: hoverTimer

        interval: 300
        onTriggered: {
            const p = d.pending
            if (!p)
                return
            if (p.row)
                d.openSubmenu(p.depth, p.row, p.entryId)
            else
                d.closeFrom(p.depth)
        }
    }
}
