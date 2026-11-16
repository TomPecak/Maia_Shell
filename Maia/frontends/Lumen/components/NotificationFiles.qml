pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import LumenFrontend

// The files of a notification (a screenshot, a download, a file from a phone). One file with a
// preview is shown large; otherwise one row per file (its preview or its type's icon, its name),
// at most maximumRows. A click opens a file, a drag hands it to another application (Dolphin, a
// browser, a chat), the folder button opens where it is. A local file that is gone is shown, dim,
// and does nothing.
//
// The data is the role "files" of Maia.Notifications.Center (read off the GUI thread); previews are
// decoded asynchronously at their shown size. This component only shows them.
ColumnLayout {
    id: files

    // [{ url, name, mimeType, iconName, genericIconName, preview, local, exists, image }]
    property var model: []
    property int maximumRows: 3
    // A file is being dragged (the popup must not end meanwhile)
    readonly property bool dragging: dragCount > 0
    property int dragCount: 0

    signal opened(string url)

    readonly property bool large: model.length === 1 && model[0].preview.length > 0

    visible: model.length > 0
    spacing: Theme.spacingXS

    function usable(file) {
        return !file.local || file.exists
    }

    function open(url) {
        Shell.launch("xdg-open " + url)
        files.opened(url)
    }

    function openFolder(url) {
        Shell.launch("xdg-open " + url.substring(0, url.lastIndexOf("/")))
        files.opened(url)
    }

    // What every file does: open on a click, hand itself over on a drag
    component FileArea: Item {
        id: fileArea

        required property var file

        readonly property bool hovered: fileHover.hovered
        readonly property bool active: files.usable(file)

        // Dragged out of the popup as a file (text/uri-list), with a small picture of it
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: ({ "text/uri-list": [fileArea.file.url] })
        Drag.imageSource: fileArea.file.preview
        Drag.imageSourceSize: Qt.size(96, 96)
        Drag.active: fileDrag.active

        HoverHandler {
            id: fileHover
            enabled: fileArea.active
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: fileArea.active
            // Takes the press, so the card's own default action does not fire as well
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: files.open(fileArea.file.url)
        }

        DragHandler {
            id: fileDrag

            enabled: fileArea.active
            target: null
            onActiveChanged: files.dragCount += active ? 1 : -1
        }
    }

    // The type's icon: the specific one ("image-png"), else its group's ("image-x-generic")
    component TypeIcon: Item {
        id: typeIcon

        required property var file
        property int size: 32

        implicitWidth: size
        implicitHeight: size

        LIcon {
            id: specific
            anchors.centerIn: parent
            size: typeIcon.size
            iconName: typeIcon.file.iconName
            tinted: false
        }

        LIcon {
            anchors.centerIn: parent
            visible: specific.status !== Image.Ready
            size: typeIcon.size
            iconName: typeIcon.file.genericIconName.length > 0 ? typeIcon.file.genericIconName : "text-x-generic"
            tinted: false
        }
    }

    component FolderButton: SubtleButton {
        id: folderButton

        required property var file

        implicitWidth: 28
        implicitHeight: 28
        padding: 0
        Accessible.name: qsTr("Show in folder")
        contentItem: Item { LIcon { anchors.centerIn: parent; size: 16; iconName: "folder-open-symbolic" } }
        onClicked: files.openFolder(folderButton.file.url)

        LToolTip { text: folderButton.Accessible.name }
    }

    // --- One file with a preview: large ---

    Rectangle {
        id: preview

        objectName: "filePreview"
        readonly property var file: files.large ? files.model[0] : null

        Layout.fillWidth: true
        Layout.preferredHeight: 140
        visible: files.large
        radius: Theme.radiusSmall
        color: Theme.control
        clip: true

        Image {
            id: picture

            anchors.fill: parent
            source: preview.file ? preview.file.preview : ""
            // Decoded in the image loader thread at its shown size, never on the GUI thread
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            opacity: status === Image.Ready ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
        }

        TypeIcon {
            anchors.centerIn: parent
            visible: preview.file !== null && picture.status === Image.Error
            file: preview.file ?? ({ iconName: "", genericIconName: "" })
            size: 48
        }

        FileArea {
            id: previewArea

            anchors.fill: parent
            file: preview.file ?? ({ url: "", preview: "", local: false, exists: false })
        }

        FolderButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            visible: preview.file !== null && preview.file.local && preview.file.exists && previewArea.hovered
            file: preview.file ?? ({ url: "" })
        }
    }

    // --- Rows ---

    Repeater {
        model: files.large ? [] : files.model.slice(0, files.maximumRows)

        Rectangle {
            id: row

            required property var modelData

            objectName: "fileRow"
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Theme.radiusSmall
            color: rowArea.hovered ? Theme.subtleHover : "transparent"
            opacity: rowArea.active ? 1 : 0.5

            FileArea {
                id: rowArea

                anchors.fill: parent
                file: row.modelData
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                spacing: Theme.spacingS

                Item {
                    implicitWidth: 32
                    implicitHeight: 32

                    Image {
                        id: thumbnail

                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: row.modelData.preview
                        sourceSize: Qt.size(32 * Screen.devicePixelRatio, 32 * Screen.devicePixelRatio)
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                    }

                    TypeIcon {
                        anchors.fill: parent
                        visible: !thumbnail.visible
                        file: row.modelData
                    }
                }

                LText {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontCaption
                }

                FolderButton {
                    visible: row.modelData.local && row.modelData.exists && rowArea.hovered
                    file: row.modelData
                }
            }
        }
    }

    LText {
        objectName: "moreFiles"
        visible: !files.large && files.model.length > files.maximumRows
        text: qsTr("and %1 more").arg(files.model.length - files.maximumRows)
        font.pixelSize: Theme.fontCaption
        color: Theme.textSecondary
    }
}
