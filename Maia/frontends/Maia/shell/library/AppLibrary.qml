pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Controls.Basic as Controls

import org.kde.kirigami as Kirigami

import Maia.Backend as Maia
import MaiaFrontend

// App Library in the style of iPadOS 18, for the pointer and the keyboard (desktop variant; a
// touch variant comes later).
//
// It opens from its button in the dock: the panel grows out of the button and shrinks back into
// it, so it is clear where it came from and where to find it again. It lies next to the dock,
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
    // The dock button the panel grows out of and shrinks back into
    property Item originItem: null
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

    // Final place of the panel; the panel itself (sheet) moves inside it while it opens and closes
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

        Item {
            id: sheet

            width: frame.width
            height: frame.height
            opacity: 0

            RectangularShadow {
                anchors.fill: parent
                radius: background.radius
                offset.y: 18
                blur: 64
                color: Theme.shadow
            }

            Rectangle {
                id: background

                anchors.fill: parent
                radius: 26
                color: Theme.surface
                border.width: 1
                border.color: Theme.hairline

                Behavior on color {
                    ColorAnimation { duration: Theme.modeChangeDuration }
                }
            }

            // Clicks on the panel outside of the icons do not close it
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

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

    // --- Animations (Animators: they run in the render thread) ---

    // Opening: the panel grows out of the dock button with a soft spring, the desktop dims
    ParallelAnimation {
        id: openAnimation

        OpacityAnimator { target: scrim; to: 1; duration: 250; easing.type: Easing.OutCubic }
        OpacityAnimator { target: sheet; to: 1; duration: 140; easing.type: Easing.OutCubic }
        ScaleAnimator {
            target: sheet
            to: 1
            duration: 460
            easing.type: Easing.OutBack
            easing.overshoot: 0.9
        }
        XAnimator {
            target: sheet
            to: 0
            duration: 460
            easing.type: Easing.OutBack
            easing.overshoot: 0.9
        }
        YAnimator {
            target: sheet
            to: 0
            duration: 460
            easing.type: Easing.OutBack
            easing.overshoot: 0.9
        }
    }

    // Closing: the panel shrinks back into the dock button, it fades out on the way
    ParallelAnimation {
        id: closeAnimation

        onFinished: library.shown = library.open

        OpacityAnimator { target: scrim; to: 0; duration: 240; easing.type: Easing.OutCubic }
        ScaleAnimator { target: sheet; to: d.closedScale; duration: 300; easing.type: Easing.InOutCubic }
        XAnimator { target: sheet; to: d.origin.x; duration: 300; easing.type: Easing.InOutCubic }
        YAnimator { target: sheet; to: d.origin.y; duration: 300; easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            OpacityAnimator { target: sheet; to: 0; duration: 200; easing.type: Easing.InCubic }
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

        // Scale of the panel at the dock button
        readonly property real closedScale: 0.15
        // Center of the dock button relative to the center of the panel's final place
        property point origin: Qt.point(0, 0)
        // The panel closes because an application was launched
        property bool launching: false

        function updateOrigin() {
            if (!library.originItem) {
                origin = Qt.point(0, 0)
                return
            }
            const button = library.originItem.mapToItem(frame, library.originItem.width / 2,
                                                        library.originItem.height / 2)
            origin = Qt.point(button.x - frame.width / 2, button.y - frame.height / 2)
        }

        function show() {
            closeAnimation.stop()
            launchAnimation.stop()
            launching = false
            updateOrigin()
            if (!library.shown) {
                // From the dock button; a panel still closing turns around where it is
                scrim.opacity = 0
                sheet.opacity = 0
                sheet.scale = closedScale
                sheet.x = origin.x
                sheet.y = origin.y
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
                updateOrigin()
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
