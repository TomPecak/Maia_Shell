import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.layershell 1.0 as LayerShell

import LumenFrontend

// Start menu, centered above the taskbar.
//
// Pages: "home" (pinned applications and recommended files), "all" (all applications,
// alphabetically) and search results (shown while the search field is not empty).
// The applications come from the Maia backend (appsListModel), the recommended files
// and the power actions are mock-ups.
FlyoutWindow {
    id: startMenu

    flyoutName: "start"
    cardWidth: 640
    cardHeight: 640
    edges: LayerShell.Window.AnchorBottom

    readonly property bool hasAppsModel: typeof appsListModel !== "undefined" && appsListModel !== null
    readonly property bool searching: searchField.text.length > 0
    property string page: "home"

    onOpened: searchField.forceActiveFocus()

    onOpenChanged: {
        if (!open) {
            searchField.text = ""
            page = "home"
        }
    }

    Component.onCompleted: {
        // All applications sorted by name (NameRole of the backend model)
        if (hasAppsModel) {
            appsListModel.sortCaseSensitivity = Qt.CaseInsensitive
            appsListModel.sortRole = Qt.UserRole + 1
            appsListModel.sort(0)
        }
    }

    // Pinned applications (mock selection of common KDE applications)
    readonly property var pinnedApps: [
        { name: qsTr("Files"), icon: "system-file-manager", exec: "lumen:files" },
        { name: qsTr("Firefox"), icon: "firefox", exec: "firefox" },
        { name: qsTr("Terminal"), icon: "utilities-terminal", exec: "konsole" },
        { name: qsTr("Kate"), icon: "kate", exec: "kate" },
        { name: qsTr("Discover"), icon: "plasmadiscover", exec: "plasma-discover" },
        { name: qsTr("Settings"), icon: "systemsettings", exec: "systemsettings" },
        { name: qsTr("Calculator"), icon: "accessories-calculator", exec: "kcalc" },
        { name: qsTr("Screenshot"), icon: "spectacle", exec: "spectacle" },
        { name: qsTr("Documents"), icon: "okular", exec: "okular" },
        { name: qsTr("Photos"), icon: "gwenview", exec: "gwenview" },
        { name: qsTr("Music"), icon: "elisa", exec: "elisa" },
        { name: qsTr("System Monitor"), icon: "utilities-system-monitor", exec: "plasma-systemmonitor" }
    ]

    // Recommended files (mock data)
    readonly property var recommended: [
        { name: "Project plan.odt", icon: "x-office-document", time: qsTr("Recently opened") },
        { name: "Holidays 2026.jpg", icon: "image-x-generic", time: qsTr("Yesterday at 18:40") },
        { name: "notes.md", icon: "text-x-generic", time: qsTr("Monday") },
        { name: "Budget.ods", icon: "x-office-spreadsheet", time: qsTr("Last week") }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- Search ---

        SearchBox {
            id: searchField

            Layout.fillWidth: true
            Layout.margins: Theme.spacingXL
            Layout.bottomMargin: Theme.spacingL
            placeholderText: qsTr("Search for apps, settings and documents")

            onTextChanged: {
                if (startMenu.hasAppsModel)
                    appsListModel.setFilterFixedString(text)
                resultsView.currentIndex = 0
            }

            Keys.onDownPressed: resultsView.incrementCurrentIndex()
            Keys.onUpPressed: resultsView.decrementCurrentIndex()
            Keys.onReturnPressed: resultsView.launchCurrent()
            Keys.onEnterPressed: resultsView.launchCurrent()
        }

        // --- Pages ---

        Item {
            id: pages

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Home page: pinned applications and recommended files
            ColumnLayout {
                id: homePage

                width: pages.width
                height: pages.height
                spacing: Theme.spacingS
                x: startMenu.page === "home" ? 0 : -pages.width * 0.25
                // The page stays visible until it has faded out (the opacity Animator updates
                // the property only at its end)
                readonly property bool shown: !startMenu.searching && startMenu.page === "home"
                opacity: shown ? 1 : 0
                visible: shown || opacity > 0

                Behavior on x { XAnimator { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
                Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }

                SectionHeader {
                    title: qsTr("Pinned")
                    actionText: qsTr("All apps")
                    onActionTriggered: startMenu.page = "all"
                }

                Grid {
                    Layout.leftMargin: Theme.spacingXL
                    Layout.rightMargin: Theme.spacingXL
                    columns: 6

                    Repeater {
                        model: startMenu.pinnedApps

                        delegate: AppTile {
                            required property var modelData

                            text: modelData.name
                            iconSource: Theme.iconUrl(modelData.icon)
                            onClicked: Shell.launch(modelData.exec)
                        }
                    }
                }

                SectionHeader {
                    Layout.topMargin: Theme.spacingL
                    title: qsTr("Recommended")
                    actionText: qsTr("More")
                }

                Grid {
                    Layout.leftMargin: Theme.spacingXL
                    Layout.rightMargin: Theme.spacingXL
                    columns: 2
                    columnSpacing: Theme.spacingS

                    Repeater {
                        model: startMenu.recommended

                        delegate: ListButton {
                            required property var modelData

                            width: (pages.width - 2 * Theme.spacingXL - Theme.spacingS) / 2
                            text: modelData.name
                            subtitle: modelData.time
                            iconSource: Theme.iconUrl(modelData.icon)
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // All applications page
            ColumnLayout {
                id: allAppsPage

                width: pages.width
                height: pages.height
                spacing: Theme.spacingS
                x: startMenu.page === "all" ? 0 : pages.width * 0.25
                readonly property bool shown: !startMenu.searching && startMenu.page === "all"
                opacity: shown ? 1 : 0
                visible: shown || opacity > 0

                Behavior on x { XAnimator { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
                Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }

                SectionHeader {
                    title: qsTr("All apps")
                    actionText: qsTr("Back")
                    onActionTriggered: startMenu.page = "home"
                }

                AppListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: startMenu.hasAppsModel && !startMenu.searching ? appsListModel : null
                }
            }

            // Search results
            ColumnLayout {
                width: pages.width
                height: pages.height
                spacing: Theme.spacingS
                opacity: startMenu.searching ? 1 : 0
                visible: startMenu.searching || opacity > 0

                Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }

                SectionHeader {
                    title: resultsView.count > 0 ? qsTr("Best matches") : qsTr("No results")
                }

                AppListView {
                    id: resultsView

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: startMenu.hasAppsModel && startMenu.searching ? appsListModel : null
                    highlightCurrent: true
                }
            }
        }

        // --- Footer: user and power ---

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Theme.card
            bottomLeftRadius: Theme.radiusLarge
            bottomRightRadius: Theme.radiusLarge

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.divider
            }

            SubtleButton {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXL
                anchors.verticalCenter: parent.verticalCenter
                height: 40
                Accessible.name: Shell.userName

                contentItem: Row {
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Theme.accent

                        LText {
                            anchors.centerIn: parent
                            text: Shell.userInitials
                            color: Theme.onAccent
                            font.weight: Font.DemiBold
                        }
                    }

                    LText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Shell.userName
                    }
                }
            }

            SubtleButton {
                id: powerButton

                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXL
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                highlighted: powerMenu.visible
                Accessible.name: qsTr("Power")
                onClicked: powerMenu.visible ? powerMenu.close() : powerMenu.open()

                contentItem: Item {
                    LIcon { anchors.centerIn: parent; iconName: "system-shutdown-symbolic" }
                }

                PowerMenu {
                    id: powerMenu

                    x: powerButton.width - width
                    y: -height - Theme.spacingS
                }
            }
        }
    }

    // --- Local components ---

    // Section title with an optional action button on the right
    component SectionHeader: RowLayout {
        id: header

        property string title
        property string actionText
        signal actionTriggered()

        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacingXL + Theme.spacingS
        Layout.rightMargin: Theme.spacingXL

        LText {
            Layout.fillWidth: true
            text: header.title
            font.weight: Font.DemiBold
        }

        SubtleButton {
            visible: header.actionText.length > 0
            leftPadding: Theme.spacingM
            rightPadding: Theme.spacingM
            onClicked: header.actionTriggered()
            background: Rectangle {
                radius: Theme.radiusSmall
                color: parent.pressed ? Theme.subtlePressed : parent.hovered ? Theme.controlStrong : Theme.control
                border.width: 1
                border.color: Theme.stroke
            }
            contentItem: Row {
                spacing: Theme.spacingXS
                LText { text: header.actionText; font.pixelSize: Theme.fontCaption }
                LIcon { anchors.verticalCenter: parent.verticalCenter; size: 10; iconName: "go-next-symbolic" }
            }
        }
    }

    // Row with an icon, a title and an optional subtitle
    component ListButton: SubtleButton {
        id: listButton

        property url iconSource
        property string subtitle

        height: subtitle.length > 0 ? 56 : 44
        padding: Theme.spacingS
        leftPadding: Theme.spacingM

        contentItem: RowLayout {
            spacing: Theme.spacingM

            Image {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                sourceSize: Qt.size(28, 28)
                source: listButton.iconSource
                asynchronous: true
            }

            Column {
                Layout.fillWidth: true

                LText {
                    width: parent.width
                    text: listButton.text
                }
                LText {
                    width: parent.width
                    text: listButton.subtitle
                    visible: listButton.subtitle.length > 0
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textSecondary
                }
            }
        }
    }

    // List of applications from the backend model (roles: name, exec, icon)
    component AppListView: ListView {
        id: list

        property bool highlightCurrent: false

        function launchCurrent() {
            if (currentItem)
                Shell.launch(currentItem.appExec)
        }

        leftMargin: Theme.spacingXL
        rightMargin: Theme.spacingXL
        spacing: 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false

        // Roles are read through 'model', the 'icon' role would clash with AbstractButton.icon
        delegate: ListButton {
            required property var model
            readonly property string appExec: model.exec

            width: list.width - list.leftMargin - list.rightMargin
            text: model.name
            iconSource: "image://backend_app_icon/" + model.icon
            highlighted: list.highlightCurrent && ListView.isCurrentItem
            onClicked: Shell.launch(appExec)
        }

        // Thin scroll indicator on the right
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            y: list.visibleArea.yPosition * list.height
            width: 3
            height: list.visibleArea.heightRatio * list.height
            radius: 1.5
            color: Theme.textTertiary
            visible: list.visibleArea.heightRatio < 1
            opacity: list.moving ? 0.8 : 0.3

            Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
        }
    }

    // Power menu: signing out, then the power actions the system offers (Shell.powerAction)
    component PowerMenu: T.Popup {
        id: menu

        padding: Theme.spacingXS
        implicitWidth: 200
        implicitHeight: menuColumn.implicitHeight + topPadding + bottomPadding

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
                NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast; easing.type: Theme.easingExit }
        }

        background: Rectangle {
            radius: Theme.radiusMedium
            color: Theme.surface
            border.width: 1
            border.color: Theme.stroke
        }

        contentItem: Column {
            id: menuColumn

            Repeater {
                // Actions the system does not offer are left out, not shown disabled
                model: [
                    { text: qsTr("Sign out"), icon: "system-log-out-symbolic", action: "logout", available: true, separatorAfter: true },
                    { text: qsTr("Sleep"), icon: "system-suspend-symbolic", action: "suspend", available: Shell.canSuspend },
                    { text: qsTr("Restart"), icon: "system-reboot-symbolic", action: "reboot", available: Shell.canReboot },
                    { text: qsTr("Shut down"), icon: "system-shutdown-symbolic", action: "shutdown", available: Shell.canPowerOff }
                ].filter(entry => entry.available)

                delegate: Column {
                    required property var modelData

                    width: menu.availableWidth

                    SubtleButton {
                        width: parent.width
                        height: 36
                        leftPadding: Theme.spacingM
                        Accessible.name: modelData.text
                        onClicked: {
                            menu.close()
                            Shell.powerAction(modelData.action)
                        }

                        contentItem: Row {
                            spacing: Theme.spacingM
                            LIcon { anchors.verticalCenter: parent.verticalCenter; iconName: modelData.icon }
                            LText { anchors.verticalCenter: parent.verticalCenter; text: modelData.text }
                        }
                    }

                    // Separates ending the session from the power actions
                    Item {
                        visible: modelData.separatorAfter === true
                        width: parent.width
                        height: Theme.spacingS + 1

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 2 * Theme.spacingS
                            height: 1
                            color: Theme.stroke
                        }
                    }
                }
            }
        }
    }
}
