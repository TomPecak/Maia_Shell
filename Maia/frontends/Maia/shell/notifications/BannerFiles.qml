pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.kirigami.primitives as Primitives

import MaiaFrontend

// The files of a notification, in an expanded banner. One file with a preview is shown large;
// otherwise one row per file, at most maximumRows. A tap opens a file, a drag hands it to another
// application, the folder button opens where it is. A local file that is gone is shown, dim, and
// does nothing.
//
// The data is the role "files" of Maia.Notifications.Center (read off the GUI thread); previews are
// decoded asynchronously at their shown size. This component only shows them and says what was
// asked: what opens a file is the banner's window.
Column {
    id: files

    // [{ url, name, mimeType, iconName, genericIconName, preview, local, exists, image }]
    property var model: []
    property int maximumRows: 3
    readonly property bool large: model.length === 1 && model[0].preview.length > 0
    // A file is being dragged out (the banner must not end meanwhile)
    readonly property bool dragging: dragCount > 0
    property int dragCount: 0

    signal openRequested(string url)

    visible: model.length > 0
    spacing: 4

    function usable(file) {
        return !file.local || file.exists
    }

    function folderOf(url) {
        return url.substring(0, url.lastIndexOf("/"))
    }

    // What every file does: open on a tap, hand itself over on a drag
    component FileArea: Item {
        id: fileArea

        required property var file

        readonly property bool hovered: fileHover.hovered
        readonly property bool active: files.usable(file)

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
            // Takes the press, so the banner's own tap and swipe do not start as well
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: files.openRequested(fileArea.file.url)
        }

        DragHandler {
            id: fileDrag

            enabled: fileArea.active
            target: null
            onActiveChanged: files.dragCount += active ? 1 : -1
        }
    }

    component FolderButton: BannerButton {
        id: folderButton

        required property var file

        round: true
        plateSize: 32
        glyph: Qt.resolvedUrl("../../assets/icons/folder-open-symbolic.svg")
        text: qsTr("Show in folder")
        onClicked: files.openRequested(files.folderOf(folderButton.file.url))
    }

    // --- One file with a preview: large ---

    Item {
        id: preview

        objectName: "filePreview"
        readonly property var file: files.large ? files.model[0] : null

        width: files.width
        height: 168
        visible: files.large

        Primitives.ShadowedImage {
            id: picture

            anchors.fill: parent
            radius: 14
            color: Theme.secondaryFill
            source: preview.file ? preview.file.preview : ""
            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }

        FileArea {
            id: previewArea

            anchors.fill: parent
            file: preview.file ?? ({ url: "", preview: "", local: false, exists: false })
        }

        FolderButton {
            anchors.top: parent.top
            anchors.right: parent.right
            visible: preview.file !== null && preview.file.local && preview.file.exists
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
            width: files.width
            height: 52
            radius: 12
            color: rowArea.hovered ? Theme.fill : Theme.secondaryFill
            opacity: rowArea.active ? 1 : 0.5

            FileArea {
                id: rowArea

                anchors.fill: parent
                file: row.modelData
            }

            Item {
                id: rowIcon

                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32

                Primitives.ShadowedImage {
                    id: thumbnail

                    anchors.fill: parent
                    visible: row.modelData.preview.length > 0
                    radius: 6
                    color: "transparent"
                    source: row.modelData.preview
                    sourceSize: Qt.size(32 * Screen.devicePixelRatio, 32 * Screen.devicePixelRatio)
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                }

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !thumbnail.visible
                    source: row.modelData.iconName
                    fallback: row.modelData.genericIconName.length > 0 ? row.modelData.genericIconName : "text-x-generic"
                }
            }

            Text {
                anchors.left: rowIcon.right
                anchors.leftMargin: 10
                anchors.right: rowFolder.visible ? rowFolder.left : parent.right
                anchors.rightMargin: rowFolder.visible ? 0 : 12
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.name
                elide: Text.ElideMiddle
                color: Theme.label
                font.pixelSize: 14
            }

            FolderButton {
                id: rowFolder

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.modelData.local && row.modelData.exists
                file: row.modelData
            }
        }
    }

    Text {
        objectName: "moreFiles"
        visible: !files.large && files.model.length > files.maximumRows
        text: qsTr("and %1 more").arg(files.model.length - files.maximumRows)
        color: Theme.secondaryLabel
        font.pixelSize: 13
    }
}
