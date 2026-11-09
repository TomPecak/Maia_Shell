pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

import Maia.Backend as Maia
import MaiaFrontend
import ".."

// The Control Center's place in the dock strip, at the other end of the strip than the power
// button: the time and the state of Wi-Fi, the volume and the battery, read at a glance; a click
// opens the Control Center, which unfolds from here (its modules gather in this corner of the
// screen, as in the top right corner of iPadOS).
//
// Along a horizontal strip one line ("14:37" and the icons); along a vertical one the hours above
// the minutes, as on a watch band, and the icons below, so it stays as narrow as the dock. Moves
// with the dock like the power button (StripItem.qml).
StripItem {
    id: area

    property ControlCenterState controlCenter
    // The Control Center is open (the button looks pressed meanwhile)
    property bool checked: false

    signal clicked()

    width: plate.width
    height: plate.height

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Control Center, %1").arg(d.hours + ":" + d.minutes)
    Accessible.onPressAction: area.clicked()

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

        width: area.vertical ? 56 : row.width + 2 * 16
        height: area.vertical ? column.height + 2 * 12 : 42
        radius: area.vertical ? 18 : height / 2
        color: mouseArea.pressed || area.checked ? Theme.platePressed
             : mouseArea.containsMouse ? Theme.plateHover
             : Theme.dock
        border.width: 1
        border.color: Theme.hairline
        scale: mouseArea.pressed ? 0.94 : mouseArea.containsMouse ? 1.04 : 1

        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            ScaleAnimator { duration: 160; easing.type: Easing.OutCubic }
        }

        // Vertical strip: hours above minutes, then the icons
        Column {
            id: column

            anchors.centerIn: parent
            visible: area.vertical
            spacing: 10

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: d.hours
                    color: Theme.label
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: d.minutes
                    color: Theme.label
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Repeater {
                    model: d.indicators

                    StatusIcon {
                        required property string modelData
                        source: modelData
                    }
                }
            }
        }

        // Horizontal strip: one line
        Row {
            id: row

            anchors.centerIn: parent
            visible: !area.vertical
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: d.hours + ":" + d.minutes
                color: Theme.label
                font.pixelSize: 15
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: d.indicators

                    StatusIcon {
                        required property string modelData
                        source: modelData
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: plate
        hoverEnabled: true
        onClicked: area.clicked()
    }

    Maia.MaskArea {
        anchors.fill: plate
    }

    component StatusIcon: Kirigami.Icon {
        width: 16
        height: 16
        isMask: true
        color: Theme.label
    }

    QtObject {
        id: d

        property date now: new Date()
        readonly property string hours: Qt.formatTime(now, "HH")
        readonly property string minutes: Qt.formatTime(now, "mm")

        readonly property var indicators: area.controlCenter
                                          ? [area.controlCenter.wifiIcon, area.controlCenter.volumeIcon,
                                             area.controlCenter.batteryIcon]
                                          : []
    }

    // Ticks at the start of every minute, so the minutes change when the clock's do
    Timer {
        id: clock

        running: true
        triggeredOnStart: true
        onTriggered: {
            d.now = new Date()
            interval = (60 - d.now.getSeconds()) * 1000 - d.now.getMilliseconds() + 50
            restart()
        }
    }
}
