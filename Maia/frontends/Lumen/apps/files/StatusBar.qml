import QtQuick

import LumenFrontend
import "MockFileSystem.js" as Fs

// Status bar: the number of items, the selection with its size, and quick switches of the view
Item {
    id: status

    required property var explorer
    readonly property var tab: explorer.currentTab

    implicitHeight: 28

    Row {
        x: Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingM

        LText {
            text: !status.tab || status.tab.path === "start" && !status.tab.searching ? ""
                : status.explorer.itemCount(status.tab.entries.length)
            font.pixelSize: Theme.fontCaption
            color: Theme.textSecondary
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 12
            color: Theme.divider
            visible: selectionLabel.visible
        }

        LText {
            id: selectionLabel

            visible: status.tab && status.tab.selected.length > 0
            text: {
                if (!visible)
                    return ""
                const count = status.explorer.selectedCount(status.tab.selected.length)
                return status.tab.selectedSize > 0 ? count + "   " + Fs.formatSize(status.tab.selectedSize) : count
            }
            font.pixelSize: Theme.fontCaption
            color: Theme.textSecondary
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ExplorerButton {
            implicitWidth: 26
            implicitHeight: 24
            iconName: "view-list-details-symbolic"
            iconSize: 14
            toolTip: qsTr("Details")
            highlighted: status.tab && status.tab.viewMode === "details"
            onClicked: status.explorer.setView("details")
        }
        ExplorerButton {
            implicitWidth: 26
            implicitHeight: 24
            iconName: "view-list-icons-symbolic"
            iconSize: 14
            toolTip: qsTr("Large icons")
            highlighted: status.tab && status.tab.viewMode !== "details"
            onClicked: status.explorer.setView("large")
        }
    }
}
