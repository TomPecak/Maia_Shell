pragma ComponentBehavior: Bound

import QtQuick

import LumenFrontend
import "MockFileSystem.js" as Fs

// Details pane on the right: a large icon, the name, the type and the properties of
// the selected item, of several selected items, or of the current folder.
Item {
    id: pane

    required property var explorer
    readonly property var tab: explorer.currentTab
    readonly property var selection: tab ? tab.selectedEntries : []
    readonly property var entry: selection.length === 1 ? selection[0] : null
    readonly property bool folderInfo: selection.length === 0

    // Properties shown in the list: [{ label, value }]
    readonly property var properties: {
        if (!tab)
            return []
        if (entry) {
            const list = [{ label: qsTr("Type"), value: entry.type }]
            if (!entry.folder)
                list.push({ label: qsTr("Size"), value: Fs.formatSize(entry.size) })
            else if (!entry.drive)
                list.push({ label: qsTr("Contains"), value: pane.explorer.itemCount(Fs.children(tab.entryPath(entry)).length) })
            if (entry.drive) {
                list.push({ label: qsTr("Used space"), value: Fs.formatSize(entry.used) })
                list.push({ label: qsTr("Free space"), value: Fs.formatSize(entry.size - entry.used) })
            } else {
                list.push({ label: qsTr("Date modified"), value: Fs.formatDate(entry.modified, Qt.locale()) })
            }
            list.push({ label: qsTr("Location"), value: Fs.toLocation(entry.location || tab.path) })
            return list
        }
        if (selection.length > 1)
            return [{ label: qsTr("Total size"), value: Fs.formatSize(tab.selectedSize) }]
        return [
            { label: qsTr("Items"), value: String(tab.entries.length) },
            { label: qsTr("Location"), value: Fs.toLocation(tab.path) }
        ]
    }

    clip: true

    Rectangle {
        anchors.left: parent.left
        width: 1
        height: parent.height
        color: Theme.divider
    }

    Column {
        x: Theme.spacingXL
        y: Theme.spacingXL
        width: pane.width - 2 * Theme.spacingXL
        spacing: Theme.spacingM

        // Two icons: switching the source (theme / own symbolic icons) of one icon together
        // with its name would try to load the name from the wrong source for a moment
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96

            LIcon {
                visible: pane.selection.length <= 1
                iconName: pane.entry ? Fs.entryIcon(pane.entry.location || pane.tab.path, pane.entry)
                        : pane.tab ? pane.tab.icon : "folder"
                tinted: false
                size: 96
            }

            LIcon {
                visible: pane.selection.length > 1
                iconName: "edit-select-all-symbolic"
                tint: Theme.textSecondary
                size: 96
            }
        }

        LText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            text: pane.entry ? pane.entry.name
                : pane.selection.length > 1 ? pane.explorer.selectedCount(pane.selection.length)
                : pane.tab ? pane.tab.title : ""
            font.pixelSize: Theme.fontSubtitle - 2
            font.weight: Font.DemiBold
        }

        LText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: text.length > 0
            text: pane.entry ? pane.entry.type : pane.folderInfo ? qsTr("Folder") : ""
            color: Theme.textSecondary
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.divider
        }

        LText {
            text: qsTr("Properties")
            font.pixelSize: Theme.fontCaption
            font.weight: Font.DemiBold
            color: Theme.textSecondary
        }

        Repeater {
            model: pane.properties

            delegate: Column {
                id: propertyRow

                required property var modelData

                width: parent ? parent.width : 0
                spacing: 2

                LText {
                    text: propertyRow.modelData.label
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textTertiary
                }
                LText {
                    width: parent.width
                    text: propertyRow.modelData.value
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                }
            }
        }
    }
}
