import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

import Maia.Backend as Maia
import MaiaFrontend

// Round power button of the status area: opens the session screen (sleep, restart, shut down,
// log out). It only opens a screen, so it acts at once; the actions themselves are one more,
// deliberate click away.
Item {
    id: button

    // The session screen is open (the button looks pressed meanwhile)
    property bool checked: false

    signal clicked()

    implicitWidth: 42
    implicitHeight: 42

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Power")
    Accessible.onPressAction: button.clicked()

    RectangularShadow {
        anchors.fill: plate
        radius: plate.radius
        offset.y: 2
        blur: 12
        color: Qt.rgba(0, 0, 0, 0.18)
        scale: plate.scale
    }

    Rectangle {
        id: plate

        anchors.fill: parent
        radius: width / 2
        color: area.pressed || button.checked ? Theme.platePressed
             : area.containsMouse ? Theme.plateHover
             : Theme.dock
        border.width: 1
        border.color: Theme.hairline
        scale: area.pressed ? 0.9 : area.containsMouse ? 1.06 : 1

        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            ScaleAnimator { duration: 160; easing.type: Easing.OutCubic }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 20
            height: 20
            // Shipped with the frontend (assets/icons/README.md)
            source: Qt.resolvedUrl("../../assets/icons/system-shutdown-symbolic.svg")
            isMask: true
            color: Theme.label
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: button.clicked()
    }

    Maia.MaskArea {
        anchors.fill: parent
    }
}
