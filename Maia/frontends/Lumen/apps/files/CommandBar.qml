import QtQuick
import QtQuick.Layouts

import LumenFrontend

// Command bar: New, the clipboard and file commands, Sort, View, more commands and
// the details pane. The commands are enabled by the selection and the folder.
Item {
    id: commands

    required property var explorer
    readonly property var tab: explorer.currentTab
    readonly property bool hasSelection: tab ? tab.selected.length > 0 : false
    readonly property bool canModify: tab ? tab.canModify : false

    implicitHeight: 44

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        spacing: 2

        ExplorerButton {
            iconName: "list-add-symbolic"
            text: qsTr("New")
            dropdown: true
            enabled: commands.canModify
            onClicked: commands.explorer.popupMenuBelow(commands.explorer.newMenu(), this)
        }

        Divider {}

        ExplorerButton {
            iconName: "edit-cut-symbolic"
            toolTip: qsTr("Cut (Ctrl+X)")
            enabled: commands.hasSelection && commands.canModify
            onClicked: commands.explorer.copySelection(true)
        }
        ExplorerButton {
            iconName: "edit-copy-symbolic"
            toolTip: qsTr("Copy (Ctrl+C)")
            enabled: commands.hasSelection
            onClicked: commands.explorer.copySelection(false)
        }
        ExplorerButton {
            iconName: "edit-paste-symbolic"
            toolTip: qsTr("Paste (Ctrl+V)")
            enabled: commands.explorer.clipboard !== null && commands.canModify
            onClicked: commands.explorer.paste()
        }
        ExplorerButton {
            iconName: "edit-rename-symbolic"
            toolTip: qsTr("Rename (F2)")
            enabled: commands.tab && commands.tab.selected.length === 1 && commands.canModify
            onClicked: commands.explorer.renameSelection()
        }
        ExplorerButton {
            iconName: "document-share-symbolic"
            toolTip: qsTr("Share")
            enabled: commands.hasSelection
            onClicked: commands.explorer.showToast(qsTr("Sharing is not available in this preview"))
        }
        ExplorerButton {
            iconName: "edit-delete-symbolic"
            toolTip: commands.tab && commands.tab.path === "trash" ? qsTr("Delete permanently (Delete)") : qsTr("Delete (Delete)")
            enabled: commands.hasSelection && commands.canModify
            onClicked: commands.explorer.deleteSelection()
        }

        Divider {}

        ExplorerButton {
            iconName: "view-sort-symbolic"
            text: qsTr("Sort")
            dropdown: true
            onClicked: commands.explorer.popupMenuBelow(commands.explorer.sortMenu(), this)
        }
        ExplorerButton {
            iconName: commands.tab && commands.tab.viewMode === "details" ? "view-list-details-symbolic" : "view-list-icons-symbolic"
            text: qsTr("View")
            dropdown: true
            onClicked: commands.explorer.popupMenuBelow(commands.explorer.viewMenu(), this)
        }

        Divider {
            visible: emptyTrash.visible
        }

        ExplorerButton {
            id: emptyTrash

            visible: commands.tab && commands.tab.path === "trash" && !commands.tab.searching
            iconName: "user-trash-symbolic"
            text: qsTr("Empty Recycle Bin")
            enabled: commands.tab && commands.tab.entries.length > 0
            onClicked: commands.explorer.emptyTrash()
        }

        ExplorerButton {
            iconName: "view-more-horizontal-symbolic"
            toolTip: qsTr("See more")
            onClicked: commands.explorer.popupMenuBelow(commands.explorer.moreMenu(), this)
        }

        Item { Layout.fillWidth: true }

        ExplorerButton {
            iconName: "view-right-new-symbolic"
            text: qsTr("Details")
            highlighted: commands.explorer.detailsPaneVisible
            toolTip: qsTr("Show the details pane (Alt+Shift+P)")
            onClicked: commands.explorer.detailsPaneVisible = !commands.explorer.detailsPaneVisible
        }
    }

    component Divider: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 20
        Layout.leftMargin: Theme.spacingXS
        Layout.rightMargin: Theme.spacingXS
        color: Theme.divider
    }
}
