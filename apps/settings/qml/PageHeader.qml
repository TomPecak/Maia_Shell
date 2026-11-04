import QtQuick
import QtQuick.Layouts

import LumenFrontend

// Breadcrumb title (Windows 11): "Wi-Fi › Saved networks". The earlier parts are links back, the
// current one is plain; a back button is not needed besides it.
RowLayout {
    id: header

    // Titles from the first page to the current one
    property var titles: []

    signal crumbClicked(int index)

    spacing: Theme.spacingS

    Repeater {
        model: header.titles

        RowLayout {
            id: crumb

            required property string modelData
            required property int index
            readonly property bool last: index === header.titles.length - 1

            spacing: Theme.spacingS
            Layout.fillWidth: last

            LText {
                text: crumb.modelData
                font.pixelSize: Theme.fontTitle
                font.weight: Font.DemiBold
                color: crumb.last ? Theme.textPrimary : link.containsMouse ? Theme.textPrimary : Theme.textSecondary
                elide: Text.ElideRight
                Layout.fillWidth: crumb.last

                MouseArea {
                    id: link
                    anchors.fill: parent
                    enabled: !crumb.last
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: header.crumbClicked(crumb.index)
                }
            }

            LIcon {
                visible: !crumb.last
                iconName: "go-next-symbolic"
                size: 16
                tint: Theme.textSecondary
            }
        }
    }
}
