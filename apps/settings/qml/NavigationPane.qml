import QtQuick
import QtQuick.Layouts

import LumenFrontend

// The left pane: search and the list of pages. The search filters the list as one types (with
// accents ignored); Enter opens the first page left.
ColumnLayout {
    id: pane

    property string currentPageId

    signal pageSelected(string pageId)

    spacing: Theme.spacingM

    function focusSearch() {
        search.forceActiveFocus()
        search.selectAll()
    }

    RowLayout {
        spacing: Theme.spacingM
        Layout.leftMargin: Theme.spacingS
        Layout.topMargin: Theme.spacingS

        LIcon { iconName: "configure-symbolic"; size: 16 }
        LText { text: qsTr("Settings"); font.pixelSize: Theme.fontCaption }
    }

    SearchBox {
        id: search

        placeholderText: qsTr("Find a setting")
        Layout.fillWidth: true
        Accessible.name: qsTr("Find a setting")
        Keys.onReturnPressed: {
            for (let i = 0; i < Pages.count; ++i) {
                if (Pages.matches(i, text)) {
                    pane.pageSelected(Pages.get(i).pageId)
                    return
                }
            }
        }
        Keys.onDownPressed: list.forceActiveFocus()
    }

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2
        clip: true
        model: Pages
        keyNavigationEnabled: true

        delegate: SubtleButton {
            id: item

            required property int index
            required property string pageId
            required property string name
            required property string iconName
            readonly property bool current: pageId === pane.currentPageId
            readonly property bool found: Pages.matches(index, search.text)

            width: ListView.view.width
            height: found ? 36 : 0
            visible: found
            highlighted: current
            Accessible.name: name
            onClicked: pane.pageSelected(pageId)

            contentItem: RowLayout {
                spacing: Theme.spacingM

                LIcon {
                    iconName: item.iconName
                    size: 16
                    Layout.leftMargin: Theme.spacingM
                }

                LText {
                    text: item.name
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // The selection pill (Windows 11 navigation view)
            Rectangle {
                visible: item.current
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 16
                radius: 1.5
                color: Theme.accent
            }
        }
    }

    LText {
        visible: search.text.length > 0 && !hasResults
        readonly property bool hasResults: {
            for (let i = 0; i < Pages.count; ++i) {
                if (Pages.matches(i, search.text))
                    return true
            }
            return false
        }
        text: qsTr("No results")
        color: Theme.textSecondary
        Layout.leftMargin: Theme.spacingM
    }
}
