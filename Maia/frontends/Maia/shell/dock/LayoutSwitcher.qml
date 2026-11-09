import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// TEMPORARY, for trying out the layouts of the Control Center button (ControlCenterButton.qml):
// "‹ 2 ›" on a dock plate, the arrows go to the previous and the next layout, the number is the
// current one (its name in the tooltip of the screen reader). Remove with the layouts not chosen.
Rectangle {
    id: switcher

    // 0-based current layout, the number of layouts and the name of the current one
    property int current: 0
    property int count: 1
    property string currentName

    signal previousRequested()
    signal nextRequested()

    radius: width * 0.2
    color: Theme.plate

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Control Center button layout: %1").arg(currentName)

    Row {
        anchors.centerIn: parent

        Arrow {
            next: false
            onClicked: switcher.previousRequested()
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            horizontalAlignment: Text.AlignHCenter
            text: switcher.current + 1
            color: Theme.label
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Arrow {
            next: true
            onClicked: switcher.nextRequested()
        }
    }

    component Arrow: Rectangle {
        id: arrow

        property bool next: true

        signal clicked()

        width: 21
        height: switcher.height - 12
        radius: 8
        color: area.pressed ? Theme.platePressed : area.containsMouse ? Theme.plateHover : "transparent"

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
