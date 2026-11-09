import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// TEMPORARY, for trying out the layouts of the Control Center button (ControlCenterButton.qml): a
// module of one cell with "‹ 2 ›" and the name of the layout below; the arrows go to the previous
// and the next one. Remove with the layouts not chosen.
ModulePlatter {
    id: tile

    // 0-based current layout, the number of layouts and the name of the current one
    property int current: 0
    property int count: 1
    property string currentName

    signal layoutRequested(int layout)

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Control Center button layout: %1").arg(currentName)

    Column {
        anchors.centerIn: parent
        spacing: 2

        Row {
            anchors.horizontalCenter: parent.horizontalCenter

            Arrow {
                next: false
                onClicked: tile.layoutRequested((tile.current + tile.count - 1) % tile.count)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                horizontalAlignment: Text.AlignHCenter
                text: tile.current + 1
                color: Theme.label
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Arrow {
                next: true
                onClicked: tile.layoutRequested((tile.current + 1) % tile.count)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.currentName
            color: Theme.secondaryLabel
            font.pixelSize: 11
        }
    }

    component Arrow: Rectangle {
        id: arrow

        property bool next: true

        signal clicked()

        width: 26
        height: 30
        radius: 9
        color: area.pressed ? Theme.pressed : area.containsMouse ? Theme.hover : "transparent"

        Accessible.role: Accessible.Button
        Accessible.name: next ? qsTr("Next layout") : qsTr("Previous layout")
        Accessible.onPressAction: arrow.clicked()

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 14
            height: 14
            source: Qt.resolvedUrl(arrow.next ? "../../assets/icons/go-next-symbolic.svg"
                                              : "../../assets/icons/go-previous-symbolic.svg")
            isMask: true
            color: Theme.label
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            onClicked: arrow.clicked()
        }
    }
}
