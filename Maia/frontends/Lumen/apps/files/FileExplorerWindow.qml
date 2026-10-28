pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import LumenFrontend
import "MockFileSystem.js" as Fs

// File Explorer of Lumen: a mock-up of a file manager in the style of the shell (and of the
// current Windows Explorer). It works on an in-memory file system (MockFileSystem.js), so
// everything can be clicked and tried without touching real files: tabs, navigation with
// history, breadcrumb and typed locations, search, views, sorting, selection, new folders,
// rename, cut / copy / paste, the Recycle Bin, menus and keyboard shortcuts.
//
// It is a normal application window (not a layer-shell surface), without the decoration of
// the compositor: the tab strip is the title bar, the edges resize the window.
Window {
    id: explorer

    // --- Tabs ---

    property var tabs: []
    property int currentIndex: 0
    readonly property var currentTab: tabs.length > 0 ? tabs[Math.min(currentIndex, tabs.length - 1)] : null
    // The tab added last (only it animates in the tab strip)
    property var lastAddedTab: null

    // --- State ---

    // Bumped after every change of the mock file system, the views read it again
    property int revision: 0
    // { from, names, cut } or null
    property var clipboard: null
    property bool detailsPaneVisible: false
    readonly property bool maximized: visibility === Window.Maximized || visibility === Window.FullScreen

    width: Math.min(1180, Screen.desktopAvailableWidth - 80)
    height: Math.min(720, Screen.desktopAvailableHeight - 80)
    minimumWidth: 760
    minimumHeight: 480
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: currentTab ? currentTab.title + " — " + qsTr("File Explorer") : qsTr("File Explorer")

    Component.onCompleted: {
        Fs.init(typeof HOME !== "undefined" ? String(HOME) : "")
        // Names read before the initialization (e.g. of the home folder) are read again
        revision++
        newTab("start")
        focusView()
    }

    // --- Shell integration (taskbar button) ---

    onActiveChanged: {
        if (!active)
            menuLayer.hide()
    }
    onClosing: {
        // The window is destroyed after the close has been handled
        Qt.callLater(() => Shell.fileExplorerOpen = false)
    }

    Connections {
        target: Shell

        // A click on the taskbar button: restore, bring to the front or minimize
        function onFileExplorerActivationRequested() {
            if (explorer.visibility === Window.Minimized || explorer.visibility === Window.Hidden) {
                explorer.show()
                explorer.raise()
                explorer.requestActivate()
            } else if (explorer.active) {
                explorer.showMinimized()
            } else {
                explorer.raise()
                explorer.requestActivate()
            }
        }
    }

    Component {
        id: tabComponent

        ExplorerTab {
            revision: explorer.revision
        }
    }

    // ========================================================================
    // Functions used by the parts of the window
    // ========================================================================

    function newTab(path) {
        const tab = tabComponent.createObject(explorer, { path: Fs.exists(path) ? path : "start" })
        lastAddedTab = tab
        tabs = tabs.concat([tab])
        currentIndex = tabs.length - 1
        Qt.callLater(() => lastAddedTab = null)
    }

    function closeTab(index) {
        if (tabs.length <= 1) {
            close()
            return
        }
        const tab = tabs[index]
        const list = tabs.slice()
        list.splice(index, 1)
        if (currentIndex > index || currentIndex === list.length)
            currentIndex = Math.max(0, currentIndex - 1)
        tabs = list
        tab.destroy()
    }

    function toggleMaximized() {
        if (maximized)
            showNormal()
        else
            showMaximized()
    }

    function focusView() {
        fileView.forceActiveFocus()
    }

    function refresh() {
        revision++
    }

    function itemCount(count) {
        return count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(count)
    }

    function selectedCount(count) {
        return count === 1 ? qsTr("1 item selected") : qsTr("%1 items selected").arg(count)
    }

    function showToast(text) {
        toast.show(text)
    }

    // --- Opening ---

    function openEntry(entry, inNewTab) {
        if (!entry)
            return
        if (entry.folder) {
            const path = Fs.join(entry.location || currentTab.path, entry.name)
            if (inNewTab)
                newTab(path)
            else
                currentTab.navigate(path)
            return
        }
        showToast(qsTr("“%1” can't be opened in this preview").arg(entry.name))
    }

    function openSelection(inNewTab) {
        const entries = currentTab.selectedEntries
        if (entries.length === 1)
            openEntry(entries[0], inNewTab)
        else
            entries.filter(entry => entry.folder).forEach(entry => openEntry(entry, true))
    }

    function openLocation(entry) {
        if (currentTab.navigate(entry.location))
            currentTab.selectName(entry.name)
    }

    // --- Changes of the mock file system ---

    function newItem(kind) {
        const tab = currentTab
        if (!tab.canModify)
            return
        const names = {
            "folder": qsTr("New folder"),
            "text": qsTr("New text document.txt"),
            "spreadsheet": qsTr("New spreadsheet.ods"),
            "presentation": qsTr("New presentation.odp")
        }
        const name = Fs.create(tab.path, names[kind], kind === "folder")
        if (name.length === 0)
            return
        revision++
        tab.selectName(name)
        tab.renaming = name
    }

    function renameSelection() {
        const tab = currentTab
        if (tab.canModify && tab.selected.length === 1)
            tab.renaming = tab.selected[0]
    }

    function finishRename(oldName, newName) {
        const tab = currentTab
        if (tab.renaming !== oldName)
            return
        tab.renaming = ""
        const name = newName.trim()
        if (name === oldName)
            return
        if (Fs.rename(tab.path, oldName, name)) {
            revision++
            tab.selectName(name)
        } else {
            showToast(name.length === 0 ? qsTr("The name can't be empty")
                                        : qsTr("“%1” already exists in this folder").arg(name))
        }
    }

    function copySelection(cut) {
        const tab = currentTab
        if (tab.selected.length === 0 || tab.searching || (cut && !tab.canModify))
            return
        clipboard = { from: tab.path, names: tab.selected.slice(), cut: cut }
        const count = tab.selected.length
        showToast(cut ? (count === 1 ? qsTr("Cut 1 item") : qsTr("Cut %1 items").arg(count))
                      : (count === 1 ? qsTr("Copied 1 item") : qsTr("Copied %1 items").arg(count)))
    }

    function paste() {
        const tab = currentTab
        if (!clipboard || !tab.canModify)
            return
        const names = clipboard.names
        const count = Fs.paste(tab.path, clipboard)
        if (clipboard.cut)
            clipboard = null
        revision++
        if (count > 0) {
            tab.selected = tab.entries.filter(entry => names.indexOf(entry.name) >= 0).map(entry => entry.name)
            showToast(count === 1 ? qsTr("Pasted 1 item") : qsTr("Pasted %1 items").arg(count))
        }
    }

    function deleteSelection() {
        const tab = currentTab
        if (tab.selected.length === 0 || !tab.canModify)
            return
        const permanent = tab.path === "trash"
        const count = Fs.remove(tab.path, tab.selected.slice())
        if (clipboard && clipboard.from === tab.path)
            clipboard = null
        revision++
        tab.clearSelection()
        if (permanent)
            showToast(count === 1 ? qsTr("Deleted 1 item") : qsTr("Deleted %1 items").arg(count))
        else
            showToast(count === 1 ? qsTr("Moved 1 item to the Recycle Bin") : qsTr("Moved %1 items to the Recycle Bin").arg(count))
    }

    function emptyTrash() {
        const names = Fs.children("trash").map(entry => entry.name)
        if (names.length === 0)
            return
        Fs.remove("trash", names)
        revision++
        showToast(qsTr("The Recycle Bin is empty"))
    }

    // --- View ---

    function sortBy(role) {
        const tab = currentTab
        if (tab.sortRole === role) {
            tab.sortAscending = !tab.sortAscending
        } else {
            tab.sortRole = role
            tab.sortAscending = role === "name" || role === "type"
        }
    }

    function setView(mode) {
        currentTab.viewMode = mode
    }

    // ========================================================================
    // Menus: lists of { text, icon, shortcut, enabled, checked, action } or { separator }
    // ========================================================================

    readonly property var separator: ({ separator: true })

    function newMenu() {
        return [
            { text: qsTr("Folder"), icon: "folder-new-symbolic", shortcut: "Ctrl+Shift+N", action: () => newItem("folder") },
            separator,
            { text: qsTr("Text document"), icon: "document-new-symbolic", action: () => newItem("text") },
            { text: qsTr("Spreadsheet"), icon: "document-new-symbolic", action: () => newItem("spreadsheet") },
            { text: qsTr("Presentation"), icon: "document-new-symbolic", action: () => newItem("presentation") }
        ]
    }

    function sortMenu() {
        const tab = currentTab
        const item = (text, role) => ({ text: text, checked: tab.sortRole === role, action: () => {
            tab.sortRole = role
        } })
        return [
            item(qsTr("Name"), "name"),
            item(qsTr("Date modified"), "modified"),
            item(qsTr("Type"), "type"),
            item(qsTr("Size"), "size"),
            separator,
            { text: qsTr("Ascending"), checked: tab.sortAscending, action: () => tab.sortAscending = true },
            { text: qsTr("Descending"), checked: !tab.sortAscending, action: () => tab.sortAscending = false }
        ]
    }

    function viewItems() {
        const tab = currentTab
        return [
            { text: qsTr("Large icons"), checked: tab.viewMode === "large", shortcut: "Ctrl+Shift+2", action: () => setView("large") },
            { text: qsTr("Medium icons"), checked: tab.viewMode === "medium", shortcut: "Ctrl+Shift+3", action: () => setView("medium") },
            { text: qsTr("Details"), checked: tab.viewMode === "details", shortcut: "Ctrl+Shift+6", action: () => setView("details") }
        ]
    }

    function viewMenu() {
        return viewItems().concat([
            separator,
            { text: qsTr("Details pane"), checked: detailsPaneVisible, shortcut: "Alt+Shift+P",
              action: () => detailsPaneVisible = !detailsPaneVisible }
        ])
    }

    function moreMenu() {
        const tab = currentTab
        return [
            { text: qsTr("Select all"), icon: "edit-select-all-symbolic", shortcut: "Ctrl+A", enabled: tab.entries.length > 0, action: () => tab.selectAll() },
            { text: qsTr("Select none"), icon: "edit-select-none-symbolic", enabled: tab.selected.length > 0, action: () => tab.clearSelection() },
            { text: qsTr("Invert selection"), icon: "edit-select-invert-symbolic", enabled: tab.entries.length > 0, action: () => tab.invertSelection() },
            separator,
            { text: qsTr("Options"), icon: "configure-symbolic", enabled: false }
        ]
    }

    // Menu of the selected items
    function itemMenu() {
        const tab = currentTab
        const entries = tab.selectedEntries
        const single = entries.length === 1
        const folder = single && entries[0].folder
        const items = [
            { text: qsTr("Open"), icon: "document-open-symbolic", shortcut: "Enter", action: () => openSelection(false) }
        ]
        if (folder)
            items.push({ text: qsTr("Open in new tab"), icon: "tab-new-symbolic", action: () => openSelection(true) })
        if (tab.searching && single)
            items.push({ text: qsTr("Open file location"), icon: "folder-open-symbolic", action: () => openLocation(entries[0]) })
        items.push(separator,
            { text: qsTr("Cut"), icon: "edit-cut-symbolic", shortcut: "Ctrl+X", enabled: tab.canModify, action: () => copySelection(true) },
            { text: qsTr("Copy"), icon: "edit-copy-symbolic", shortcut: "Ctrl+C", enabled: !tab.searching, action: () => copySelection(false) },
            { text: qsTr("Rename"), icon: "edit-rename-symbolic", shortcut: "F2", enabled: single && tab.canModify, action: () => renameSelection() },
            { text: tab.path === "trash" ? qsTr("Delete permanently") : qsTr("Delete"), icon: "edit-delete-symbolic",
              shortcut: "Delete", enabled: tab.canModify, action: () => deleteSelection() },
            separator,
            { text: qsTr("Pin to Quick access"), icon: "pin-symbolic", enabled: false },
            { text: qsTr("Properties"), icon: "document-properties-symbolic", shortcut: "Alt+Enter", action: () => detailsPaneVisible = true })
        return items
    }

    // Menu of the free space in a folder
    function folderMenu() {
        const tab = currentTab
        return viewItems().concat([
            separator,
            { text: qsTr("New folder"), icon: "folder-new-symbolic", shortcut: "Ctrl+Shift+N", enabled: tab.canModify, action: () => newItem("folder") },
            separator,
            { text: qsTr("Paste"), icon: "edit-paste-symbolic", shortcut: "Ctrl+V", enabled: clipboard !== null && tab.canModify, action: () => paste() },
            { text: qsTr("Refresh"), icon: "view-refresh-symbolic", shortcut: "F5", action: () => refresh() },
            { text: qsTr("Select all"), icon: "edit-select-all-symbolic", shortcut: "Ctrl+A", enabled: tab.entries.length > 0, action: () => tab.selectAll() },
            separator,
            { text: qsTr("Open in Terminal"), icon: "utilities-terminal-symbolic", enabled: false },
            { text: qsTr("Properties"), icon: "document-properties-symbolic", action: () => { tab.clearSelection(); detailsPaneVisible = true } }
        ])
    }

    // Menu of a place (navigation pane, Quick access, drives)
    function placeMenu(path, pinned) {
        return [
            { text: qsTr("Open"), icon: "document-open-symbolic", action: () => currentTab.navigate(path) },
            { text: qsTr("Open in new tab"), icon: "tab-new-symbolic", action: () => newTab(path) },
            separator,
            { text: pinned ? qsTr("Unpin from Quick access") : qsTr("Pin to Quick access"), icon: "pin-symbolic", enabled: false },
            { text: qsTr("Properties"), icon: "document-properties-symbolic", action: () => {
                currentTab.navigate(path)
                detailsPaneVisible = true
            } }
        ]
    }

    // Menu of a file in the Recent list of the Home page
    function recentMenu(entry) {
        return [
            { text: qsTr("Open"), icon: "document-open-symbolic", action: () => openEntry(entry, false) },
            { text: qsTr("Open file location"), icon: "folder-open-symbolic", action: () => openLocation(entry) },
            separator,
            { text: qsTr("Remove from Recent"), icon: "edit-delete-symbolic", enabled: false }
        ]
    }

    // Subfolders of a breadcrumb segment
    function popupSubfolders(path, item) {
        const folders = Fs.children(path).filter(entry => entry.folder)
        const items = folders.map(entry => ({
            text: entry.drive ? entry.name + " (" + entry.mount + ")" : Fs.displayName(Fs.join(path, entry.name)),
            icon: "folder-symbolic",
            action: () => currentTab.navigate(Fs.join(path, entry.name))
        }))
        popupMenuBelow(items.length > 0 ? items : [{ text: qsTr("No subfolders"), enabled: false }], item)
    }

    function popupMenu(items, x, y) {
        menuLayer.show(items, x, y)
    }

    function popupMenuBelow(items, item) {
        const position = item.mapToItem(null, 0, item.height + 2)
        popupMenu(items, position.x, position.y)
    }

    // ========================================================================
    // Keyboard shortcuts
    // ========================================================================

    Shortcut { sequence: "Ctrl+T"; onActivated: explorer.newTab("start") }
    Shortcut { sequence: "Ctrl+W"; onActivated: explorer.closeTab(explorer.currentIndex) }
    Shortcut { sequences: ["Ctrl+Tab"]; onActivated: explorer.currentIndex = (explorer.currentIndex + 1) % explorer.tabs.length }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]; onActivated: explorer.currentIndex = (explorer.currentIndex + explorer.tabs.length - 1) % explorer.tabs.length }
    Shortcut { sequences: ["Alt+Left", "Backspace"]; onActivated: explorer.currentTab.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: explorer.currentTab.goForward() }
    Shortcut { sequence: "Alt+Up"; onActivated: explorer.currentTab.goUp() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; onActivated: explorer.refresh() }
    Shortcut { sequences: ["Ctrl+L", "Alt+D", "F4"]; onActivated: navigationBar.editAddress() }
    Shortcut { sequences: ["Ctrl+F", "Ctrl+E", "F3"]; onActivated: navigationBar.focusSearch() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: explorer.newItem("folder") }
    Shortcut { sequence: "Ctrl+A"; onActivated: explorer.currentTab.selectAll() }
    Shortcut { sequence: "Ctrl+C"; onActivated: explorer.copySelection(false) }
    Shortcut { sequence: "Ctrl+X"; onActivated: explorer.copySelection(true) }
    Shortcut { sequence: "Ctrl+V"; onActivated: explorer.paste() }
    Shortcut { sequence: "Delete"; onActivated: explorer.deleteSelection() }
    Shortcut { sequence: "F2"; onActivated: explorer.renameSelection() }
    Shortcut { sequence: "Alt+Return"; onActivated: explorer.detailsPaneVisible = true }
    Shortcut { sequence: "Alt+Shift+P"; onActivated: explorer.detailsPaneVisible = !explorer.detailsPaneVisible }
    Shortcut { sequence: "Ctrl+Shift+2"; onActivated: explorer.setView("large") }
    Shortcut { sequence: "Ctrl+Shift+3"; onActivated: explorer.setView("medium") }
    Shortcut { sequence: "Ctrl+Shift+6"; onActivated: explorer.setView("details") }
    Shortcut {
        sequence: "Escape"
        // Text fields (address, search, rename) handle Escape themselves
        enabled: menuLayer.open || fileView.activeFocus
        onActivated: {
            if (menuLayer.open)
                menuLayer.hide()
            else
                explorer.currentTab.clearSelection()
        }
    }

    // ========================================================================
    // Layout
    // ========================================================================

    readonly property int cornerRadius: maximized ? 0 : Theme.radiusMedium

    Rectangle {
        id: frame

        anchors.fill: parent
        radius: explorer.cornerRadius
        color: Theme.windowChrome

        Behavior on color { ColorAnimation { duration: Theme.durationNormal } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: explorer.maximized ? 0 : 1
            spacing: 0

            TabStrip {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                explorer: explorer
            }

            // Toolbars and content, below the tabs
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.windowToolbar
                bottomLeftRadius: Math.max(0, explorer.cornerRadius - 1)
                bottomRightRadius: Math.max(0, explorer.cornerRadius - 1)

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    NavigationBar {
                        id: navigationBar

                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        explorer: explorer
                    }

                    CommandBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        explorer: explorer
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.divider
                    }

                    // Content area
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.windowContent
                        bottomLeftRadius: Math.max(0, explorer.cornerRadius - 1)
                        bottomRightRadius: Math.max(0, explorer.cornerRadius - 1)

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 0

                                Sidebar {
                                    Layout.preferredWidth: 232
                                    Layout.fillHeight: true
                                    explorer: explorer
                                }

                                Rectangle {
                                    Layout.preferredWidth: 1
                                    Layout.fillHeight: true
                                    color: Theme.divider
                                }

                                FileView {
                                    id: fileView

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    explorer: explorer
                                    focus: true
                                }

                                DetailsPane {
                                    Layout.preferredWidth: explorer.detailsPaneVisible ? 300 : 0
                                    Layout.fillHeight: true
                                    visible: Layout.preferredWidth > 0
                                    explorer: explorer

                                    Behavior on Layout.preferredWidth {
                                        NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingStandard }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Theme.divider
                            }

                            StatusBar {
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight
                                explorer: explorer
                            }
                        }
                    }
                }
            }
        }

        // Hairline border of the window, above the content
        Rectangle {
            anchors.fill: parent
            radius: explorer.cornerRadius
            color: "transparent"
            border.width: explorer.maximized ? 0 : 1
            border.color: Theme.stroke
        }
    }

    // --- Resizing by the edges and corners ---

    ResizeArea { edges: Qt.LeftEdge; x: 0; y: 12; width: 5; height: explorer.height - 24 }
    ResizeArea { edges: Qt.RightEdge; x: explorer.width - 5; y: 12; width: 5; height: explorer.height - 24 }
    ResizeArea { edges: Qt.TopEdge; x: 12; y: 0; width: explorer.width - 24; height: 4 }
    ResizeArea { edges: Qt.BottomEdge; x: 12; y: explorer.height - 5; width: explorer.width - 24; height: 5 }
    ResizeArea { edges: Qt.TopEdge | Qt.LeftEdge; x: 0; y: 0; width: 12; height: 12 }
    ResizeArea { edges: Qt.TopEdge | Qt.RightEdge; x: explorer.width - 12; y: 0; width: 12; height: 12 }
    ResizeArea { edges: Qt.BottomEdge | Qt.LeftEdge; x: 0; y: explorer.height - 12; width: 12; height: 12 }
    ResizeArea { edges: Qt.BottomEdge | Qt.RightEdge; x: explorer.width - 12; y: explorer.height - 12; width: 12; height: 12 }

    component ResizeArea: Item {
        id: resizeArea

        property int edges

        visible: !explorer.maximized
        z: 50

        HoverHandler {
            cursorShape: resizeArea.edges === Qt.LeftEdge || resizeArea.edges === Qt.RightEdge ? Qt.SizeHorCursor
                       : resizeArea.edges === Qt.TopEdge || resizeArea.edges === Qt.BottomEdge ? Qt.SizeVerCursor
                       : resizeArea.edges === (Qt.TopEdge | Qt.LeftEdge) || resizeArea.edges === (Qt.BottomEdge | Qt.RightEdge)
                         ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
        }

        DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: {
                if (active)
                    explorer.startSystemResize(resizeArea.edges)
            }
        }
    }

    // --- Menus ---

    Item {
        id: menuLayer

        property var items: []
        property real menuX: 0
        property real menuY: 0
        readonly property bool open: menu.open

        function show(list, x, y) {
            items = list
            menuX = x
            menuY = y
            if (menu.open)
                menu.replay()
            else
                menu.open = true
        }

        function hide() {
            menu.open = false
        }

        // Always visible: the menu controls its own visibility, the area below catches
        // clicks only while the menu is open
        anchors.fill: parent
        z: 100

        // A click outside closes the menu
        MouseArea {
            anchors.fill: parent
            enabled: menu.open
            acceptedButtons: Qt.AllButtons
            onPressed: menuLayer.hide()
        }

        LMenu {
            id: menu

            readonly property bool openUp: menuLayer.menuY + height > menuLayer.height - 8

            implicitWidth: 248
            openUpwards: openUp
            x: Math.max(8, Math.min(menuLayer.menuX, menuLayer.width - width - 8))
            y: openUp ? Math.max(8, menuLayer.menuY - height) : menuLayer.menuY

            Repeater {
                model: menuLayer.items

                delegate: Item {
                    id: menuEntry

                    required property var modelData
                    readonly property bool isSeparator: modelData.separator === true
                    readonly property bool checkable: modelData.checked !== undefined

                    width: menu.width
                    height: isSeparator ? separatorItem.implicitHeight : menuItem.implicitHeight

                    LMenuSeparator {
                        id: separatorItem

                        width: parent.width
                        visible: menuEntry.isSeparator
                    }

                    LMenuItem {
                        id: menuItem

                        width: parent.width
                        visible: !menuEntry.isSeparator
                        text: menuEntry.modelData.text || ""
                        shortcut: menuEntry.modelData.shortcut || ""
                        iconName: menuEntry.checkable ? (menuEntry.modelData.checked ? "checkmark-symbolic" : "")
                                                      : (menuEntry.modelData.icon || "")
                        iconColor: menuEntry.checkable ? Theme.accent : Theme.textPrimary
                        enabled: menuEntry.modelData.enabled !== false
                        onClicked: {
                            menuLayer.hide()
                            if (menuEntry.modelData.action)
                                menuEntry.modelData.action()
                        }
                    }
                }
            }
        }
    }

    // --- Short messages (copied, moved to the Recycle Bin, ...) ---

    Item {
        id: toast

        property string text

        function show(message) {
            text = message
            hideAnimation.stop()
            hideTimer.restart()
            bubble.opacity = 0
            bubble.y = 12
            showAnimation.restart()
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        width: bubble.width
        height: bubble.height
        z: 90

        Rectangle {
            id: bubble

            width: toastLabel.implicitWidth + 2 * Theme.spacingL
            height: 36
            radius: height / 2
            color: Theme.surface
            border.width: 1
            border.color: Theme.stroke
            opacity: 0
            visible: opacity > 0 || showAnimation.running

            LText {
                id: toastLabel

                anchors.centerIn: parent
                text: toast.text
            }
        }

        ParallelAnimation {
            id: showAnimation

            OpacityAnimator { target: bubble; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
            YAnimator { target: bubble; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
        }

        ParallelAnimation {
            id: hideAnimation

            OpacityAnimator { target: bubble; to: 0; duration: Theme.durationFast; easing.type: Theme.easingExit }
            YAnimator { target: bubble; to: 6; duration: Theme.durationFast; easing.type: Theme.easingExit }
        }

        Timer {
            id: hideTimer

            interval: 2600
            onTriggered: hideAnimation.start()
        }
    }
}
