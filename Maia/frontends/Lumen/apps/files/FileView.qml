pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

import LumenFrontend
import "MockFileSystem.js" as Fs

// Content of the current tab: the Home page (Quick access and Recent), This PC (folders and
// drives) or a folder, shown as details (sortable columns) or as large / medium icons.
//
// Mouse: click selects (Ctrl toggles, Shift selects a range), double click opens, the middle
// button opens a folder in a new tab, the right button shows the menu of the item or of the
// folder. Keyboard: arrows, Home / End (with Shift), Enter opens. The content slides in
// after every navigation.
FocusScope {
    id: view

    required property var explorer
    readonly property var tab: explorer.currentTab
    readonly property var entries: tab ? tab.entries : []
    readonly property string page: !tab ? ""
                                 : tab.searching ? "folder"
                                 : tab.path === "start" ? "home"
                                 : tab.path === "this-pc" ? "pc"
                                 : "folder"
    // Item names of the clipboard when it holds a cut from this folder (shown dimmed)
    readonly property var cutNames: explorer.clipboard && explorer.clipboard.cut && tab
                                    && explorer.clipboard.from === tab.path ? explorer.clipboard.names : []

    // --- Interaction shared by the views ---

    function pressEntry(index, mouse, item) {
        view.forceActiveFocus()
        const entry = entries[index]
        if (!entry)
            return
        if (mouse.button === Qt.MiddleButton) {
            if (entry.folder)
                explorer.newTab(tab.entryPath(entry))
            return
        }
        if (mouse.button === Qt.RightButton) {
            if (!tab.isSelected(entry.name))
                tab.select(index, "single")
            const position = item.mapToItem(null, mouse.x, mouse.y)
            explorer.popupMenu(explorer.itemMenu(), position.x, position.y)
            return
        }
        const mode = (mouse.modifiers & Qt.ControlModifier) ? "toggle"
                   : (mouse.modifiers & Qt.ShiftModifier) ? "range"
                   : "single"
        tab.select(index, mode)
    }

    function pressBackground(mouse, item) {
        view.forceActiveFocus()
        if (tab.renaming.length > 0)
            return
        if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
            tab.clearSelection()
        if (mouse.button === Qt.RightButton) {
            const position = item.mapToItem(null, mouse.x, mouse.y)
            explorer.popupMenu(explorer.folderMenu(), position.x, position.y)
        }
    }

    function moveCurrent(step, extend) {
        if (entries.length === 0)
            return
        const from = tab.currentIndex < 0 ? (step > 0 ? -1 : entries.length) : tab.currentIndex
        const index = Math.max(0, Math.min(entries.length - 1, from + step))
        tab.select(index, extend ? "range" : "single")
        if (pages.item && pages.item.positionAt)
            pages.item.positionAt(index)
    }

    Keys.onPressed: event => {
        if (page !== "folder" || tab.renaming.length > 0)
            return
        const columns = pages.item && pages.item.columns ? pages.item.columns : 1
        const extend = (event.modifiers & Qt.ShiftModifier) !== 0
        switch (event.key) {
        case Qt.Key_Down: moveCurrent(columns, extend); break
        case Qt.Key_Up: moveCurrent(-columns, extend); break
        case Qt.Key_Right: if (columns > 1) moveCurrent(1, extend); else return; break
        case Qt.Key_Left: if (columns > 1) moveCurrent(-1, extend); else return; break
        case Qt.Key_Home: moveCurrent(-entries.length, extend); break
        case Qt.Key_End: moveCurrent(entries.length, extend); break
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (tab.currentIndex >= 0)
                explorer.openEntry(entries[tab.currentIndex], false)
            break
        default:
            return
        }
        event.accepted = true
    }

    // --- Transition after a navigation ---

    function playTransition() {
        transition.stop()
        pageHolder.opacity = 0
        pageHolder.y = 8
        transition.start()
    }

    Connections {
        target: view.tab

        function onPathChanged() { view.playTransition() }
        function onSearchingChanged() { view.playTransition() }
        function onViewModeChanged() { view.playTransition() }
    }
    onTabChanged: playTransition()

    ParallelAnimation {
        id: transition

        OpacityAnimator { target: pageHolder; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
        YAnimator { target: pageHolder; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
    }

    Item {
        id: pageHolder

        width: view.width
        height: view.height

        Loader {
            id: pages

            anchors.fill: parent
            sourceComponent: view.page === "home" ? homePage
                           : view.page === "pc" ? pcPage
                           : view.tab && view.tab.viewMode === "details" ? detailsView
                           : iconsView
        }

        EmptyState {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: view.page === "folder" && view.tab && view.tab.viewMode === "details" ? 16 : 0
            visible: view.page === "folder" && view.entries.length === 0
        }
    }

    // ========================================================================
    // Details view
    // ========================================================================

    Component {
        id: detailsView

        Item {
            id: details

            readonly property int columns: 1
            readonly property bool showLocation: view.tab.searching
            readonly property bool showType: width - locationWidth > 640
            readonly property int dateWidth: 150
            readonly property int typeWidth: showType ? 150 : 0
            readonly property int sizeWidth: 90
            readonly property int locationWidth: showLocation ? Math.min(220, Math.max(120, width * 0.25)) : 0
            readonly property int nameWidth: Math.max(160, width - 2 * Theme.spacingS - 12 - dateWidth - typeWidth - sizeWidth - locationWidth)

            function positionAt(index) {
                list.positionViewAtIndex(index, ListView.Contain)
            }

            // Column headers, a click sorts by the column (again: the other direction)
            Row {
                id: header

                x: Theme.spacingS + 6
                height: 32

                HeaderCell { width: details.nameWidth; label: qsTr("Name"); role: "name" }
                HeaderCell { width: details.locationWidth; visible: details.showLocation; label: qsTr("Location"); role: "" }
                HeaderCell { width: details.dateWidth; label: qsTr("Date modified"); role: "modified" }
                HeaderCell { width: details.typeWidth; visible: details.showType; label: qsTr("Type"); role: "type" }
                HeaderCell { width: details.sizeWidth; label: qsTr("Size"); role: "size"; alignRight: true }
            }

            Rectangle {
                anchors.top: header.bottom
                width: parent.width
                height: 1
                color: Theme.divider
            }

            ListView {
                id: list

                anchors.top: header.bottom
                anchors.topMargin: 1 + Theme.spacingXS
                anchors.bottom: parent.bottom
                width: parent.width
                model: view.entries
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Empty space: clears the selection, menu of the folder
                MouseArea {
                    parent: list.contentItem
                    y: list.originY
                    width: list.width
                    height: Math.max(list.height, list.contentHeight)
                    z: -1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: mouse => view.pressBackground(mouse, this)
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property var entry: modelData
                    readonly property bool selected: view.tab.selected.indexOf(entry.name) >= 0
                    readonly property bool renaming: view.tab.renaming === entry.name && !view.tab.searching

                    width: list.width
                    height: 32

                    EntryBackground {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        selected: row.selected
                        hovered: rowMouse.containsMouse
                        current: view.activeFocus && view.tab.currentIndex === row.index
                    }

                    Row {
                        x: Theme.spacingS + 6
                        height: parent.height
                        opacity: view.cutNames.indexOf(row.entry.name) >= 0 ? 0.5 : 1

                        Item {
                            width: details.nameWidth
                            height: parent.height

                            LIcon {
                                id: rowIcon

                                anchors.verticalCenter: parent.verticalCenter
                                iconName: Fs.entryIcon(row.entry.location || view.tab.path, row.entry)
                                tinted: false
                                size: 16
                            }

                            LText {
                                anchors.left: rowIcon.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.renaming
                                text: row.entry.name
                            }

                            Loader {
                                anchors.left: rowIcon.right
                                anchors.leftMargin: Theme.spacingS - 4
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                active: row.renaming
                                sourceComponent: RenameField {
                                    entryName: row.entry.name
                                }
                            }
                        }

                        CellText {
                            width: details.locationWidth
                            visible: details.showLocation
                            text: row.entry.location ? Fs.toLocation(row.entry.location) : ""
                        }
                        CellText {
                            width: details.dateWidth
                            text: Fs.formatDate(row.entry.modified, Qt.locale())
                        }
                        CellText {
                            width: details.typeWidth
                            visible: details.showType
                            text: row.entry.type
                        }
                        CellText {
                            width: details.sizeWidth
                            horizontalAlignment: Text.AlignRight
                            text: row.entry.folder ? "" : Fs.formatSize(row.entry.size)
                        }
                    }

                    MouseArea {
                        id: rowMouse

                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        enabled: !row.renaming
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onPressed: mouse => view.pressEntry(row.index, mouse, this)
                        onDoubleClicked: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                view.explorer.openEntry(row.entry, false)
                        }
                    }
                }
            }

            ScrollIndicator {
                flickable: list
            }
        }
    }

    // ========================================================================
    // Icons view
    // ========================================================================

    Component {
        id: iconsView

        Item {
            id: icons

            readonly property bool large: view.tab !== null && view.tab.viewMode === "large"
            readonly property int iconSize: large ? 64 : 48
            readonly property int cellWidth: large ? 112 : 96
            readonly property int cellHeight: large ? 124 : 104
            readonly property int columns: Math.max(1, Math.floor(grid.width / cellWidth))

            function positionAt(index) {
                grid.positionViewAtIndex(index, GridView.Contain)
            }

            GridView {
                id: grid

                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.topMargin: Theme.spacingS
                cellWidth: icons.cellWidth
                cellHeight: icons.cellHeight
                model: view.entries
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                MouseArea {
                    parent: grid.contentItem
                    y: grid.originY
                    width: grid.width
                    height: Math.max(grid.height, grid.contentHeight)
                    z: -1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: mouse => view.pressBackground(mouse, this)
                }

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index
                    readonly property var entry: modelData
                    readonly property bool selected: view.tab.selected.indexOf(entry.name) >= 0
                    readonly property bool renaming: view.tab.renaming === entry.name && !view.tab.searching

                    width: grid.cellWidth
                    height: grid.cellHeight

                    EntryBackground {
                        anchors.fill: parent
                        anchors.margins: 3
                        selected: cell.selected
                        hovered: cellMouse.containsMouse
                        current: view.activeFocus && view.tab.currentIndex === cell.index
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        width: parent.width - 12
                        spacing: 6
                        opacity: view.cutNames.indexOf(cell.entry.name) >= 0 ? 0.5 : 1

                        LIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            iconName: Fs.entryIcon(cell.entry.location || view.tab.path, cell.entry)
                            tinted: false
                            size: icons.iconSize
                        }

                        LText {
                            width: parent.width
                            visible: !cell.renaming
                            text: cell.entry.name
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Theme.fontCaption + 1
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Loader {
                            width: parent.width
                            active: cell.renaming
                            visible: active
                            sourceComponent: RenameField {
                                entryName: cell.entry.name
                                centered: true
                            }
                        }
                    }

                    MouseArea {
                        id: cellMouse

                        anchors.fill: parent
                        anchors.margins: 3
                        enabled: !cell.renaming
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onPressed: mouse => view.pressEntry(cell.index, mouse, this)
                        onDoubleClicked: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                view.explorer.openEntry(cell.entry, false)
                        }
                    }
                }
            }

            ScrollIndicator {
                flickable: grid
            }
        }
    }

    // ========================================================================
    // Home page
    // ========================================================================

    Component {
        id: homePage

        Flickable {
            id: home

            property string selectedPath: ""
            readonly property var recent: { view.explorer.revision; return Fs.recent(8) }

            contentHeight: homeColumn.height + Theme.spacingXL
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            MouseArea {
                width: home.width
                height: Math.max(home.height, home.contentHeight)
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: home.selectedPath = ""
            }

            Column {
                id: homeColumn

                x: Theme.spacingXL
                width: home.width - 2 * Theme.spacingXL
                topPadding: Theme.spacingL
                spacing: Theme.spacingM

                SectionTitle { text: qsTr("Quick access") }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: Fs.quickAccess()

                        delegate: PlaceTile {
                            required property string modelData

                            path: modelData
                            caption: qsTr("Stored locally")
                            pinned: true
                            selected: home.selectedPath === modelData
                            onSelectRequested: home.selectedPath = modelData
                        }
                    }
                }

                Item { width: 1; height: Theme.spacingS }

                SectionTitle { text: qsTr("Recent") }

                Column {
                    width: parent.width

                    Row {
                        x: 6
                        height: 28

                        CellText { width: homeColumn.width * 0.45; text: qsTr("Name"); color: Theme.textSecondary; font.pixelSize: Theme.fontCaption }
                        CellText { width: homeColumn.width * 0.2; text: qsTr("Date modified"); color: Theme.textSecondary; font.pixelSize: Theme.fontCaption }
                        CellText { width: homeColumn.width * 0.35 - 12; text: qsTr("File location"); color: Theme.textSecondary; font.pixelSize: Theme.fontCaption }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.divider
                    }

                    Item { width: 1; height: Theme.spacingXS }

                    Repeater {
                        model: home.recent

                        delegate: Item {
                            id: recentRow

                            required property var modelData
                            readonly property string key: modelData.location + "/" + modelData.name

                            width: homeColumn.width
                            height: 36

                            EntryBackground {
                                anchors.fill: parent
                                selected: home.selectedPath === recentRow.key
                                hovered: recentMouse.containsMouse
                            }

                            Row {
                                x: 6
                                height: parent.height

                                Item {
                                    width: homeColumn.width * 0.45
                                    height: parent.height

                                    LIcon {
                                        id: recentIcon

                                        anchors.verticalCenter: parent.verticalCenter
                                        iconName: recentRow.modelData.icon
                                        tinted: false
                                        size: 20
                                    }

                                    LText {
                                        anchors.left: recentIcon.right
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: recentRow.modelData.name
                                    }
                                }
                                CellText { width: homeColumn.width * 0.2; text: Fs.formatRelative(recentRow.modelData.modified) }
                                CellText { width: homeColumn.width * 0.35 - 12; text: Fs.toLocation(recentRow.modelData.location) }
                            }

                            MouseArea {
                                id: recentMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: mouse => {
                                    home.selectedPath = recentRow.key
                                    if (mouse.button === Qt.RightButton) {
                                        const position = mapToItem(null, mouse.x, mouse.y)
                                        view.explorer.popupMenu(view.explorer.recentMenu(recentRow.modelData), position.x, position.y)
                                    }
                                }
                                onDoubleClicked: view.explorer.openEntry(recentRow.modelData, false)
                            }
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // This PC
    // ========================================================================

    Component {
        id: pcPage

        Flickable {
            id: pc

            property string selectedPath: ""
            readonly property var drives: { view.explorer.revision; return Fs.children("this-pc") }

            contentHeight: pcColumn.height + Theme.spacingXL
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            MouseArea {
                width: pc.width
                height: Math.max(pc.height, pc.contentHeight)
                onPressed: pc.selectedPath = ""
            }

            Column {
                id: pcColumn

                x: Theme.spacingXL
                width: pc.width - 2 * Theme.spacingXL
                topPadding: Theme.spacingL
                spacing: Theme.spacingM

                SectionTitle { text: qsTr("Folders") }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: Fs.quickAccess()

                        delegate: PlaceTile {
                            required property string modelData

                            path: modelData
                            caption: qsTr("Stored locally")
                            selected: pc.selectedPath === modelData
                            onSelectRequested: pc.selectedPath = modelData
                        }
                    }
                }

                Item { width: 1; height: Theme.spacingS }

                SectionTitle { text: qsTr("Devices and drives") }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: pc.drives

                        delegate: DriveTile {
                            required property var modelData

                            entry: modelData
                            selected: pc.selectedPath === "this-pc/" + modelData.name
                            onSelectRequested: pc.selectedPath = "this-pc/" + modelData.name
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // Building blocks
    // ========================================================================

    // Hover, selection and keyboard focus of an entry
    component EntryBackground: Rectangle {
        property bool selected: false
        property bool hovered: false
        property bool current: false

        radius: Theme.radiusSmall
        color: selected ? (hovered ? Theme.selectionHover : Theme.selection)
             : hovered ? Theme.subtleHover
             : "transparent"
        border.width: current ? 1 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    component CellText: LText {
        height: parent ? parent.height : 0
        rightPadding: Theme.spacingM
        color: Theme.textSecondary
        font.pixelSize: Theme.fontCaption + 1
    }

    component HeaderCell: T.AbstractButton {
        id: headerCell

        property string label
        property string role
        property bool alignRight: false
        readonly property bool sorted: role.length > 0 && view.tab.sortRole === role

        height: 32
        hoverEnabled: role.length > 0
        enabled: role.length > 0
        onClicked: view.explorer.sortBy(role)

        background: Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            anchors.rightMargin: Theme.spacingXS
            radius: Theme.radiusSmall
            color: headerCell.pressed ? Theme.subtlePressed : headerCell.hovered ? Theme.subtleHover : "transparent"

            // Divider between the columns
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16
                color: Theme.divider
            }
        }

        contentItem: Item {
            LText {
                anchors.left: headerCell.alignRight ? undefined : parent.left
                anchors.right: headerCell.alignRight ? sortArrow.left : undefined
                anchors.leftMargin: 0
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                text: headerCell.label
                font.pixelSize: Theme.fontCaption
                color: Theme.textSecondary
            }

            LIcon {
                id: sortArrow

                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                visible: headerCell.sorted
                iconName: view.tab.sortAscending ? "go-up-symbolic" : "go-down-symbolic"
                size: 8
                tint: Theme.textSecondary
            }
        }
    }

    // Folder tile of the Home page and This PC
    component PlaceTile: T.AbstractButton {
        id: place

        property string path
        property string caption
        property bool pinned: false
        property bool selected: false

        signal selectRequested()

        width: 240
        height: 64
        hoverEnabled: true
        Accessible.name: Fs.displayName(path)
        onPressed: selectRequested()
        onDoubleClicked: view.tab.navigate(path)

        TapHandler {
            acceptedButtons: Qt.MiddleButton | Qt.RightButton
            onTapped: (eventPoint, button) => {
                if (button === Qt.MiddleButton) {
                    view.explorer.newTab(place.path)
                } else {
                    place.selectRequested()
                    const position = place.mapToItem(null, eventPoint.position.x, eventPoint.position.y)
                    view.explorer.popupMenu(view.explorer.placeMenu(place.path, place.pinned), position.x, position.y)
                }
            }
        }

        scale: pressed ? 0.98 : 1
        Behavior on scale { ScaleAnimator { duration: Theme.durationFast } }

        background: EntryBackground {
            selected: place.selected
            hovered: place.hovered
        }

        contentItem: Item {
            LIcon {
                id: placeIcon

                x: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                iconName: Fs.iconFor(place.path)
                tinted: false
                size: 40
            }

            Column {
                anchors.left: placeIcon.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                LText {
                    width: parent.width
                    text: Fs.displayName(place.path)
                }

                Row {
                    spacing: 4

                    LIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: place.pinned
                        iconName: "pin-symbolic"
                        size: 10
                        tint: Theme.textTertiary
                    }
                    LText {
                        text: place.caption
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textTertiary
                    }
                }
            }
        }
    }

    // Drive tile of This PC: name, usage bar and free space
    component DriveTile: T.AbstractButton {
        id: driveTile

        property var entry
        property bool selected: false
        readonly property real usage: entry.size > 0 ? entry.used / entry.size : 0

        signal selectRequested()

        width: 300
        height: 72
        hoverEnabled: true
        Accessible.name: entry.name
        onPressed: selectRequested()
        onDoubleClicked: view.tab.navigate("this-pc/" + entry.name)

        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: view.explorer.newTab("this-pc/" + driveTile.entry.name)
        }

        scale: pressed ? 0.98 : 1
        Behavior on scale { ScaleAnimator { duration: Theme.durationFast } }

        background: EntryBackground {
            selected: driveTile.selected
            hovered: driveTile.hovered
        }

        contentItem: Item {
            LIcon {
                id: driveIcon

                x: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                iconName: "drive-harddisk"
                tinted: false
                size: 40
            }

            Column {
                anchors.left: driveIcon.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                LText {
                    width: parent.width
                    text: driveTile.entry.name + " (" + driveTile.entry.mount + ")"
                }

                // Usage bar, red when the drive is almost full
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.controlStrong

                    Rectangle {
                        width: parent.width * driveTile.usage
                        height: parent.height
                        radius: 3
                        color: driveTile.usage > 0.9 ? Theme.closeHover : Theme.accent
                    }
                }

                LText {
                    text: qsTr("%1 free of %2").arg(Fs.formatSize(driveTile.entry.size - driveTile.entry.used))
                                                .arg(Fs.formatSize(driveTile.entry.size))
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textTertiary
                }
            }
        }
    }

    component SectionTitle: LText {
        font.pixelSize: Theme.fontBodyLarge
        font.weight: Font.DemiBold
    }

    // Shown when the folder (or the search) has no items
    component EmptyState: Column {
        spacing: Theme.spacingS

        LIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            iconName: view.tab && view.tab.searching ? "system-search-symbolic" : "folder-open-symbolic"
            size: 40
            tint: Theme.textTertiary
        }

        LText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !view.tab ? ""
                : view.tab.searching ? qsTr("No items match your search.")
                : view.tab.path === "trash" ? qsTr("The Recycle Bin is empty.")
                : view.tab.path === "network" ? qsTr("No network locations were found.")
                : qsTr("This folder is empty.")
            color: Theme.textSecondary
        }
    }

    // Rename in place: Enter confirms, Escape cancels, a click elsewhere confirms
    component RenameField: TextInput {
        id: field

        required property string entryName
        property bool centered: false
        property bool done: false

        height: 26
        leftPadding: 4
        rightPadding: 4
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: centered ? TextInput.AlignHCenter : TextInput.AlignLeft
        color: Theme.textPrimary
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.fontFamily
        font.pixelSize: centered ? Theme.fontCaption + 1 : Theme.fontBody
        selectByMouse: true
        clip: true
        text: entryName

        function finish(accept) {
            if (done)
                return
            done = true
            view.explorer.finishRename(entryName, accept ? text : entryName)
            view.forceActiveFocus()
        }

        Component.onCompleted: {
            forceActiveFocus()
            // The name without the extension is selected
            const dot = entryName.lastIndexOf(".")
            select(0, dot > 0 ? dot : entryName.length)
        }
        onAccepted: finish(true)
        Keys.onEscapePressed: finish(false)
        onActiveFocusChanged: {
            if (!activeFocus)
                finish(true)
        }

        Rectangle {
            z: -1
            anchors.fill: parent
            radius: Theme.radiusSmall
            color: Theme.windowContent
            border.width: 1
            border.color: Theme.accent
        }
    }

    // Thin scroll position indicator on the right edge
    component ScrollIndicator: Rectangle {
        required property Flickable flickable

        anchors.right: parent.right
        anchors.rightMargin: 3
        y: flickable.y + flickable.visibleArea.yPosition * flickable.height
        width: 3
        height: flickable.visibleArea.heightRatio * flickable.height
        radius: 1.5
        color: Theme.textTertiary
        visible: flickable.visibleArea.heightRatio < 1
        opacity: flickable.moving ? 0.8 : 0.35

        Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
    }
}
