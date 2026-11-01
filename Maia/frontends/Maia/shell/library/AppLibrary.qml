pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Controls.Basic as Controls
import QtQuick.Templates as T

import org.kde.kirigami as Kirigami

import Maia.Backend as Maia
import MaiaFrontend

// App Library in the style of iPadOS 18, for the pointer and the keyboard (desktop variant; a
// touch variant comes later).
//
// It opens from its button in the dock: the panel's shape grows out of the button and shrinks
// back into exactly its shape (place, size, corner radius and color of the button's plate), so it
// is clear where it came from and where to find it again. It lies next to the dock,
// towards the middle of the screen: the pointer starts at the button, so the way to the icons is
// short (Fitts's law). The search field has the keyboard focus at once: typing a few letters and
// Enter is the fastest way to one of a hundred or more applications; the grid below is for
// browsing (recognising an icon instead of remembering a name).
//
// Closes by a click outside of the panel, Escape (the first press clears the search), the dock
// button, or by launching an application. While it is open the rest of the desktop is dimmed; the
// dock stays above the dimming and usable.
//
// Fills the whole window; the input region of the window covers it only while it is shown.
Item {
    id: library

    // --- Public API ---

    property bool open: false
    // The dock button the panel grows out of and shrinks back into (its background is the plate
    // the panel's shape starts and ends as)
    property T.Control originItem: null
    // Edge of the dock and the strip it reserves there; the panel lies next to that strip
    property int dockEdge: Qt.BottomEdge
    property real dockStrip: 0

    // The panel asks to be closed (Escape, a click outside, an application was launched)
    signal closeRequested()
    // The panel closed without launching anything: the window that had the keyboard before
    // should get it back (the panel took it while it was open)
    signal dismissed()

    // --- Layout ---

    readonly property bool dockVertical: dockEdge === Qt.LeftEdge || dockEdge === Qt.RightEdge
    // Distance between the panel and the dock strip, and between the panel and the screen edges
    readonly property real dockGap: 12
    readonly property real screenMargin: 24
    readonly property real padding: 20
    readonly property real cellWidth: 112
    readonly property real cellHeight: 116
    readonly property int columns: Math.max(3, Math.min(7, Math.floor(
        (width - 2 * screenMargin - (dockVertical ? dockStrip + dockGap : 0) - 2 * padding) / cellWidth)))

    readonly property bool searching: searchField.text.length > 0

    // Shown from opening until the closing animation has finished. Animators write their
    // properties only when they finish, so the visibility cannot follow the opacity (see
    // MenuPanel.qml of the desktop menu).
    property bool shown: false

    visible: shown

    // Monochrome icons (Breeze actions, some application icons) are drawn in this color
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: Theme.label

    onOpenChanged: open ? d.show() : d.hide()

    // --- Applications ---

    // All applications, { name, exec, icon }, read once from the backend model
    property var applications: []
    // What the grid shows: all applications, or the matches of the search, best first
    readonly property var results: searching ? d.search(searchField.text) : applications

    onResultsChanged: {
        // While searching the best match is selected, Enter launches it
        grid.currentIndex = searching && results.length > 0 ? 0 : -1
        grid.positionViewAtBeginning()
    }

    Component.onCompleted: d.loadApplications()

    // Launches an application and closes the panel
    function launch(application) {
        if (!application)
            return
        console.log("[AppLibrary] launching", application.name, "(" + application.exec + ")")
        if (typeof backend !== "undefined" && backend)
            backend.runCommand(application.exec)
        d.launching = true
        closeRequested()
    }

    // --- Dimming of the desktop ---

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: Theme.scrim
        opacity: 0

        // A click outside of the panel closes it, nothing reaches the windows below
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: library.closeRequested()
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    // --- The panel ---

    // Final place of the panel. Inside it the shape of the panel (card) morphs between the dock
    // button and this place; the content stays at its final place and the card reveals it.
    Item {
        id: frame

        width: library.columns * library.cellWidth + 2 * library.padding
        height: Math.min(640, library.height - 2 * library.screenMargin
                         - (library.dockVertical ? 0 : library.dockStrip + library.dockGap))

        x: library.dockEdge === Qt.LeftEdge ? library.dockStrip + library.dockGap
         : library.dockEdge === Qt.RightEdge ? library.width - library.dockStrip - library.dockGap - width
         : (library.width - width) / 2
        y: library.dockEdge === Qt.TopEdge ? library.dockStrip + library.dockGap
         : library.dockEdge === Qt.BottomEdge ? library.height - library.dockStrip - library.dockGap - height
         : (library.height - height) / 2

        // Dissolves as a whole after a launch
        Item {
            id: sheet

            width: frame.width
            height: frame.height

            // Grows with the card; at the button there is no shadow of the panel
            RectangularShadow {
                x: card.x
                y: card.y
                width: card.width
                height: card.height
                radius: background.radius
                offset.y: 18 * d.settled
                blur: 64 * d.settled
                color: Theme.shadow
                opacity: Math.min(1, 2 * d.settled)
            }

            Item {
                id: card

                x: d.mix(d.button.x, 0, d.progress)
                y: d.mix(d.button.y, 0, d.progress)
                width: d.mix(d.button.width, frame.width, d.progress)
                height: d.mix(d.button.height, frame.height, d.progress)
                // Fades in and out only right at the button, where the button's own plate covers it
                opacity: Math.min(1, d.progress / 0.05)
                clip: true

                Rectangle {
                    id: background

                    anchors.fill: parent
                    radius: d.mix(d.button.radius, 26, d.settled)
                    // The plate of the button at the button, the surface of the panel when open
                    color: Qt.tint(Theme.surface, Qt.alpha(d.buttonColor, 1 - d.settled))
                    border.width: 1
                    border.color: Qt.alpha(Theme.hairline, Theme.hairline.a * d.settled)
                }

                // Clicks on the panel outside of the icons do not close it
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                // Stays at the final place of the panel while the card grows over it
                Item {
                    id: content

                    x: -card.x
                    y: -card.y
                    width: frame.width
                    height: frame.height
                    opacity: 0

                    SearchField {
                        id: searchField

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: library.padding
                        anchors.leftMargin: library.padding + 4
                        anchors.rightMargin: library.padding + 4
                        placeholderText: qsTr("App Library")

                        input.Keys.onPressed: function (event) { d.handleKey(event) }
                    }

                    GridView {
                        id: grid

                        anchors.top: searchField.bottom
                        anchors.topMargin: 12
                        anchors.bottom: parent.bottom
                        // The content is cut off inside the panel, clear of its rounded corners
                        anchors.bottomMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: library.columns * library.cellWidth
                        bottomMargin: 6

                        cellWidth: library.cellWidth
                        cellHeight: library.cellHeight
                        model: library.results
                        currentIndex: -1
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false
                        highlightFollowsCurrentItem: false

                        delegate: AppLibraryItem {
                            required property var modelData
                            required property int index

                            width: grid.cellWidth
                            height: grid.cellHeight
                            name: modelData.name
                            iconName: modelData.icon
                            selected: index === grid.currentIndex

                            onClicked: library.launch(modelData)
                        }

                        Controls.ScrollBar.vertical: Controls.ScrollBar {
                            policy: Controls.ScrollBar.AsNeeded
                        }
                    }

                    // Empty state of the search, worded like iPadOS
                    Column {
                        anchors.centerIn: grid
                        width: grid.width - 2 * library.padding
                        spacing: 6
                        visible: library.searching && library.results.length === 0

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("No Results")
                            color: Theme.label
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: qsTr("Check the spelling or try a new search.")
                            color: Theme.secondaryLabel
                            font.pixelSize: 15
                        }
                    }
                }
            }
        }
    }

    // --- Animations ---
    //
    // The shape of the panel is one number, d.progress (0: the dock button, 1: the open panel),
    // animated in the GUI thread: place, size, corner radius and color of the card follow it, so
    // they always move together. Uniform scaling (an Animator) cannot do this: a scaled panel keeps
    // its proportions and scales its corners, it can never become the square button. The content,
    // the dimming and the dissolve after a launch are Animators (render thread).

    // Opening: the shape grows out of the button with a soft spring, the content fades in once
    // there is room for it, the desktop dims
    ParallelAnimation {
        id: openAnimation

        NumberAnimation {
            target: d
            property: "progress"
            to: 1
            duration: 520
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
        }
        OpacityAnimator { target: scrim; to: 1; duration: 250; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            OpacityAnimator { target: content; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
    }

    // Closing: the content fades out first, then the shape lands in the button, decelerating, and
    // ends exactly as the button's plate
    ParallelAnimation {
        id: closeAnimation

        onFinished: library.shown = library.open

        OpacityAnimator { target: content; to: 0; duration: 110; easing.type: Easing.OutCubic }
        OpacityAnimator { target: scrim; to: 0; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation {
            target: d
            property: "progress"
            to: 0
            duration: 420
            easing.type: Easing.OutQuart
        }
    }

    // Closing after a launch: the panel does not go back to the dock (the application opens
    // elsewhere), it dissolves in place, slightly growing
    ParallelAnimation {
        id: launchAnimation

        onFinished: library.shown = library.open

        OpacityAnimator { target: scrim; to: 0; duration: 220; easing.type: Easing.OutCubic }
        OpacityAnimator { target: sheet; to: 0; duration: 180; easing.type: Easing.OutCubic }
        ScaleAnimator { target: sheet; to: 1.04; duration: 220; easing.type: Easing.OutCubic }
    }

    // --- Private ---

    QtObject {
        id: d

        // Shape of the panel: 0 at the dock button, 1 open (a little more while the spring
        // overshoots)
        property real progress: 0
        // The same, at most 1: for what must not overshoot (corner radius, color, shadow)
        readonly property real settled: Math.max(0, Math.min(1, progress))
        // The plate of the dock button as it looks on the screen, in the coordinates of frame
        property var button: ({ x: 0, y: 0, width: 0, height: 0, radius: 0 })
        readonly property color buttonColor: library.originItem && library.originItem.background
                                             ? library.originItem.background.color : Theme.plate
        // The panel closes because an application was launched
        property bool launching: false

        function mix(from, to, t) {
            return from + (to - from) * t
        }

        // Where the button's plate is now, with the scale of the button (larger under the
        // pointer) and of the dock (smaller while pressed)
        function updateButton() {
            const item = library.originItem
            if (!item) {
                button = { x: frame.width / 2, y: frame.height / 2, width: 0, height: 0, radius: 0 }
                return
            }
            const topLeft = item.mapToItem(frame, 0, 0)
            const bottomRight = item.mapToItem(frame, item.width, item.height)
            const width = bottomRight.x - topLeft.x
            const radius = item.background && item.background.radius !== undefined
                           ? item.background.radius * width / item.width : 0
            button = { x: topLeft.x, y: topLeft.y, width: width, height: bottomRight.y - topLeft.y,
                       radius: radius }
        }

        function show() {
            closeAnimation.stop()
            launchAnimation.stop()
            launching = false
            updateButton()
            if (!library.shown) {
                // From the dock button; a panel still closing turns around where it is
                progress = 0
                scrim.opacity = 0
                content.opacity = 0
                sheet.opacity = 1
                sheet.scale = 1
                searchField.text = ""
                grid.currentIndex = -1
                grid.positionViewAtBeginning()
            }
            library.shown = true
            openAnimation.restart()
            if (library.Window.window)
                library.Window.window.requestActivate()
            searchField.input.forceActiveFocus()
        }

        function hide() {
            openAnimation.stop()
            if (launching) {
                launchAnimation.restart()
            } else {
                updateButton()
                closeAnimation.restart()
                library.dismissed()
            }
        }

        function loadApplications() {
            if (typeof appsListModel === "undefined" || !appsListModel)
                return
            const nameRole = Qt.UserRole + 1
            const execRole = Qt.UserRole + 2
            const iconRole = Qt.UserRole + 3
            const list = []
            for (let row = 0; row < appsListModel.rowCount(); ++row) {
                const index = appsListModel.index(row, 0)
                const name = appsListModel.data(index, nameRole)
                const exec = appsListModel.data(index, execRole)
                if (!name || !exec)
                    continue
                list.push({ name: name, exec: exec, icon: appsListModel.data(index, iconRole) || "" })
            }
            list.sort((a, b) => a.name.localeCompare(b.name))
            library.applications = list
            console.log("[AppLibrary]", list.length, "applications")
        }

        // Matches of the search, best first: the name starts with the text, then a word of the
        // name does, then the name contains it, then the program does (e.g. "konsole"). Among
        // equal matches the shorter name first (the text covers more of it: "kon" -> "Konsola"
        // before "Konfiguracja wyglądu LXQt"), then alphabetical order.
        function search(text) {
            const query = text.trim().toLowerCase()
            if (query.length === 0)
                return library.applications
            const matches = []
            for (const application of library.applications) {
                const name = application.name.toLowerCase()
                const program = application.exec.split(" ")[0].split("/").pop().toLowerCase()
                let rank = -1
                if (name.startsWith(query))
                    rank = 0
                else if (name.split(/[\s\-_.]+/).some(word => word.startsWith(query)))
                    rank = 1
                else if (name.includes(query))
                    rank = 2
                else if (program.includes(query))
                    rank = 3
                if (rank >= 0)
                    matches.push({ rank: rank, application: application })
            }
            matches.sort((a, b) => a.rank - b.rank
                                   || a.application.name.length - b.application.name.length
                                   || a.application.name.localeCompare(b.application.name))
            return matches.map(match => match.application)
        }

        // Keyboard: typing goes to the search field. The arrows move the selection; while the
        // field holds text, left and right edit the text instead. Enter launches the selection,
        // Escape clears the search, then closes the panel.
        function handleKey(event) {
            const count = library.results.length
            const columns = library.columns
            const browsing = !library.searching
            let next = grid.currentIndex
            switch (event.key) {
            case Qt.Key_Escape:
                if (library.searching)
                    searchField.text = ""
                else
                    library.closeRequested()
                event.accepted = true
                return
            case Qt.Key_Return:
            case Qt.Key_Enter:
                library.launch(library.results[Math.max(0, grid.currentIndex)])
                event.accepted = true
                return
            case Qt.Key_Down:
                next = next < 0 ? 0 : Math.min(count - 1, next + columns)
                break
            case Qt.Key_Up:
                next = next < columns ? -1 : next - columns
                break
            case Qt.Key_Right:
                if (!browsing)
                    return
                next = Math.min(count - 1, next + 1)
                break
            case Qt.Key_Left:
                if (!browsing)
                    return
                next = Math.max(-1, next - 1)
                break
            case Qt.Key_Tab:
                next = Math.min(count - 1, next + 1)
                break
            case Qt.Key_Backtab:
                next = Math.max(-1, next - 1)
                break
            default:
                return
            }
            event.accepted = true
            if (count === 0)
                return
            grid.currentIndex = next
            if (next >= 0)
                grid.positionViewAtIndex(next, GridView.Contain)
        }
    }
}
