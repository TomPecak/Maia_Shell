pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import LumenFrontend
import "MockFileSystem.js" as Fs

// Navigation bar: back / forward / up / refresh, the address bar and the search box.
//
// The address bar shows the path as a breadcrumb; the arrow after a segment lists its
// subfolders. A click on the free space of the bar turns it into a text field with
// the location (e.g. /home/user/Documents), Enter goes there.
Item {
    id: bar

    required property var explorer
    readonly property var tab: explorer.currentTab

    function editAddress() {
        address.startEditing()
    }

    function focusSearch() {
        search.forceActiveFocus()
        search.selectAll()
    }

    implicitHeight: 48

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingM
        spacing: 2

        ExplorerButton {
            iconName: "go-previous-symbolic"
            enabled: bar.tab && bar.tab.canGoBack
            toolTip: qsTr("Back (Alt+Left)")
            onClicked: bar.tab.goBack()
        }
        ExplorerButton {
            iconName: "go-next-symbolic"
            enabled: bar.tab && bar.tab.canGoForward
            toolTip: qsTr("Forward (Alt+Right)")
            onClicked: bar.tab.goForward()
        }
        ExplorerButton {
            iconName: "go-up-symbolic"
            enabled: bar.tab && bar.tab.canGoUp
            toolTip: qsTr("Up (Alt+Up)")
            onClicked: bar.tab.goUp()
        }
        ExplorerButton {
            id: refreshButton

            iconName: "view-refresh-symbolic"
            toolTip: qsTr("Refresh (F5)")
            onClicked: bar.explorer.refresh()
        }

        AddressBar {
            id: address

            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacingS
        }

        SearchField {
            id: search

            Layout.preferredWidth: Math.min(280, bar.width * 0.28)
            Layout.leftMargin: Theme.spacingS
        }
    }

    // --- Address bar ---

    component AddressBar: Rectangle {
        id: addressBar

        property bool editing: false

        function startEditing() {
            input.text = Fs.toLocation(bar.tab.path)
            editing = true
            input.forceActiveFocus()
            input.selectAll()
        }

        function finishEditing() {
            editing = false
        }

        implicitHeight: 32
        radius: Theme.radiusSmall
        color: editing ? Theme.windowContent : Theme.control
        border.width: 1
        border.color: Theme.stroke
        transform: Translate { id: shakeOffset }

        // Not found: a short shake
        SequentialAnimation {
            id: shake

            NumberAnimation { target: shakeOffset; property: "x"; to: -6; duration: 50 }
            NumberAnimation { target: shakeOffset; property: "x"; to: 6; duration: 80 }
            NumberAnimation { target: shakeOffset; property: "x"; to: -3; duration: 70 }
            NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 60 }
        }

        // A click on the free space edits the location
        TapHandler {
            enabled: !addressBar.editing
            onTapped: addressBar.startEditing()
        }

        // Breadcrumb
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingXS
            visible: !addressBar.editing
            clip: true

            Row {
                id: crumbs

                // Long paths keep the end (the current folder) visible
                x: Math.min(0, parent.width - width)
                anchors.verticalCenter: parent.verticalCenter

                LIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: bar.tab ? bar.tab.icon : "folder"
                    tinted: false
                    size: 16
                }

                Item { width: Theme.spacingXS; height: 1 }

                Repeater {
                    model: {
                        if (!bar.tab)
                            return []
                        bar.tab.revision
                        const list = Fs.segments(bar.tab.path)
                        return bar.tab.searching ? list.concat([{ name: qsTr("Search results"), path: "" }]) : list
                    }

                    delegate: Row {
                        id: crumb

                        required property var modelData
                        required property int index

                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                        // Lists the subfolders of the segment
                        SubtleButton {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            height: 26
                            padding: 0
                            visible: crumb.modelData.path.length > 0
                            Accessible.name: qsTr("Folders in %1").arg(crumb.modelData.name)
                            onClicked: bar.explorer.popupSubfolders(crumb.modelData.path, this)

                            contentItem: Item {
                                LIcon {
                                    anchors.centerIn: parent
                                    iconName: "go-next-symbolic"
                                    size: 10
                                    tint: Theme.textSecondary
                                }
                            }
                        }

                        SubtleButton {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 26
                            leftPadding: 6
                            rightPadding: 6
                            text: crumb.modelData.name
                            onClicked: {
                                if (crumb.modelData.path.length > 0)
                                    bar.tab.navigate(crumb.modelData.path)
                            }

                            contentItem: LText {
                                text: crumb.modelData.name
                                font.pixelSize: Theme.fontBody
                            }
                        }
                    }
                }
            }
        }

        // Location editor
        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            visible: addressBar.editing
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.textPrimary
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontBody
            selectByMouse: true
            clip: true

            onAccepted: {
                const target = Fs.fromLocation(text)
                if (target.length > 0 && bar.tab.navigate(target)) {
                    addressBar.finishEditing()
                    bar.explorer.focusView()
                } else {
                    shake.restart()
                    bar.explorer.showToast(qsTr("Can't find “%1”").arg(text.trim()))
                }
            }
            Keys.onEscapePressed: {
                addressBar.finishEditing()
                bar.explorer.focusView()
            }
            onActiveFocusChanged: {
                if (!activeFocus)
                    addressBar.finishEditing()
            }
        }

        // Accent underline while editing
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: addressBar.editing ? parent.width - 2 : 0
            height: 2
            radius: 1
            color: Theme.accent

            Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
        }
    }

    // --- Search box ---

    component SearchField: T.TextField {
        id: field

        implicitHeight: 32
        leftPadding: Theme.spacingM
        rightPadding: 32
        color: Theme.textPrimary
        placeholderTextColor: Theme.textTertiary
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontBody
        verticalAlignment: TextInput.AlignVCenter
        placeholderText: bar.tab ? qsTr("Search %1").arg(Fs.displayName(bar.tab.path)) : ""
        Accessible.name: qsTr("Search")

        // The search waits for a short pause in typing
        onTextEdited: searchDelay.restart()
        Keys.onEscapePressed: {
            text = ""
            bar.tab.query = ""
            bar.explorer.focusView()
        }
        Keys.onDownPressed: bar.explorer.focusView()

        Timer {
            id: searchDelay

            interval: 250
            onTriggered: bar.tab.query = field.text.trim()
        }

        // The field follows the tab (switching tabs, navigation clears the search)
        Connections {
            target: bar.tab

            function onQueryChanged() {
                if (field.text.trim() !== bar.tab.query)
                    field.text = bar.tab.query
            }
        }
        Connections {
            target: bar.explorer

            function onCurrentTabChanged() {
                field.text = bar.tab ? bar.tab.query : ""
            }
        }

        LText {
            x: field.leftPadding
            width: field.availableWidth
            height: field.height
            text: field.placeholderText
            color: field.placeholderTextColor
            visible: !field.length && !field.preeditText
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: field.activeFocus ? Theme.windowContent : Theme.control
            border.width: 1
            border.color: Theme.stroke

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: field.activeFocus ? parent.width - 2 : 0
                height: 2
                radius: 1
                color: Theme.accent

                Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
            }
        }

        // Search icon, or the clear button while there is text
        SubtleButton {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            padding: 0
            enabled: field.length > 0
            Accessible.name: qsTr("Clear the search")
            onClicked: {
                field.text = ""
                bar.tab.query = ""
            }

            contentItem: Item {
                LIcon {
                    anchors.centerIn: parent
                    iconName: field.length > 0 ? "window-close-symbolic" : "system-search-symbolic"
                    size: field.length > 0 ? 10 : 14
                    tint: Theme.textSecondary
                }
            }
        }
    }
}
