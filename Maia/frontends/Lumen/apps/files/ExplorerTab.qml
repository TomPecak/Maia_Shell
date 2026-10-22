import QtQuick

import "MockFileSystem.js" as Fs

// State of one tab of the File Explorer: the shown folder with its history, the view,
// the sorting, the search and the selection.
QtObject {
    id: tab

    // Bumped by the window after every change of the mock file system
    property int revision: 0

    property string path: "start"
    property var backStack: []
    property var forwardStack: []

    // "details", "large" or "medium"
    property string viewMode: "details"
    // "name", "modified", "type" or "size"
    property string sortRole: "name"
    property bool sortAscending: true
    // Search in the current folder and below
    property string query: ""

    // Names of the selected entries and the anchor of a range selection (Shift)
    property var selected: []
    property int anchorIndex: -1
    property int currentIndex: -1
    // Name of the entry being renamed in place
    property string renaming: ""

    readonly property bool searching: query.length > 0
    readonly property string title: searching ? qsTr("Search results") : Fs.displayName(path)
    readonly property string icon: Fs.iconFor(path)
    readonly property bool canGoBack: backStack.length > 0
    readonly property bool canGoForward: forwardStack.length > 0
    readonly property bool canGoUp: Fs.parent(path) !== "" || path === "home"
    readonly property bool canModify: { revision; return !searching && Fs.canModify(path) }

    // Entries of the folder (or the search results): folders first, then by the sort role
    readonly property var entries: {
        revision
        const list = searching ? Fs.search(path, query) : Fs.children(path)
        const direction = sortAscending ? 1 : -1
        const key = sortRole
        list.sort((a, b) => {
            if (a.folder !== b.folder)
                return a.folder ? -1 : 1
            let result = 0
            if (key === "modified")
                result = a.modified - b.modified
            else if (key === "size")
                result = a.size - b.size
            else if (key === "type")
                result = a.type.localeCompare(b.type)
            if (result === 0)
                result = a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
            return result * direction
        })
        return list
    }

    readonly property var selectedEntries: entries.filter(entry => selected.indexOf(entry.name) >= 0)
    readonly property real selectedSize: selectedEntries.reduce((sum, entry) => sum + Math.max(0, entry.size), 0)

    // --- Navigation ---

    function navigate(target) {
        if (!Fs.exists(target))
            return false
        if (target !== path || searching) {
            backStack = backStack.concat([path])
            forwardStack = []
            show(target)
        }
        return true
    }

    function goBack() {
        if (!canGoBack)
            return
        forwardStack = forwardStack.concat([path])
        const target = backStack[backStack.length - 1]
        backStack = backStack.slice(0, -1)
        show(target)
    }

    function goForward() {
        if (!canGoForward)
            return
        backStack = backStack.concat([path])
        const target = forwardStack[forwardStack.length - 1]
        forwardStack = forwardStack.slice(0, -1)
        show(target)
    }

    function goUp() {
        if (path === "home")
            navigate("start")
        else if (canGoUp)
            navigate(Fs.parent(path))
    }

    function show(target) {
        query = ""
        renaming = ""
        clearSelection()
        path = target
    }

    // Path of an entry (search results know their own folder)
    function entryPath(entry) {
        return Fs.join(entry.location || path, entry.name)
    }

    // --- Selection ---

    function isSelected(name) {
        return selected.indexOf(name) >= 0
    }

    // mode: "single", "toggle" (Ctrl) or "range" (Shift)
    function select(index, mode) {
        const entry = entries[index]
        if (!entry)
            return
        if (mode === "toggle") {
            selected = isSelected(entry.name) ? selected.filter(name => name !== entry.name)
                                              : selected.concat([entry.name])
            anchorIndex = index
        } else if (mode === "range" && anchorIndex >= 0) {
            const from = Math.min(anchorIndex, index)
            const to = Math.max(anchorIndex, index)
            selected = entries.slice(from, to + 1).map(item => item.name)
        } else {
            selected = [entry.name]
            anchorIndex = index
        }
        currentIndex = index
    }

    function selectName(name) {
        const index = entries.findIndex(entry => entry.name === name)
        if (index >= 0)
            select(index, "single")
    }

    function selectAll() {
        selected = entries.map(entry => entry.name)
    }

    function clearSelection() {
        selected = []
        anchorIndex = -1
        currentIndex = -1
    }

    function invertSelection() {
        selected = entries.filter(entry => !isSelected(entry.name)).map(entry => entry.name)
    }

    // Keeps only the names that still exist (after a delete or a rename)
    onEntriesChanged: {
        const names = entries.map(entry => entry.name)
        const kept = selected.filter(name => names.indexOf(name) >= 0)
        if (kept.length !== selected.length)
            selected = kept
        if (currentIndex >= entries.length)
            currentIndex = entries.length - 1
    }
}
