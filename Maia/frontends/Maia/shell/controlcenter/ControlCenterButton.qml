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
// screen, as in the top right corner of iPadOS). Moves with the dock like the power button
// (StripItem.qml).
//
// Layouts (being tried out, chosen with the switcher in the dock): each has a variant along a
// vertical strip (dock at the left or right, as narrow as the dock) and along a horizontal one.
//   0 Column   vertical: hours above minutes, the icons below one another; horizontal: one line
//   1 Row      vertical: "14:37", the icons in a row below; horizontal: the time above the icons
//   2 Grid     vertical: "14:37", Wi-Fi, Bluetooth, volume, battery in two rows below;
//              horizontal: the time, the grid next to it
//   3 Analog   a clock face, the icons in a row below it (vertical) or next to it (horizontal)
StripItem {
    id: area

    property ControlCenterState controlCenter
    // The Control Center is open (the button looks pressed meanwhile)
    property bool checked: false
    // One of the layouts above
    property int layout: 0

    readonly property int layoutCount: 4
    readonly property var layoutNames: [qsTr("Column"), qsTr("Row"), qsTr("Grid"), qsTr("Analog")]

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

        // The content and the padding around it; a column narrow enough for the dock strip
        width: area.vertical ? (area.layout === 0 ? 56 : 72) : content.width + 2 * 16
        height: area.vertical ? content.height + 2 * 12 : content.height + 2 * (area.layout === 0 ? 13 : 9)
        radius: area.vertical ? 18 : (area.layout === 0 ? height / 2 : 18)
        color: mouseArea.pressed || area.checked ? Theme.platePressed
             : mouseArea.containsMouse ? Theme.plateHover
             : Theme.dock
        border.width: 1
        border.color: Theme.hairline
        scale: mouseArea.pressed ? 0.94 : mouseArea.containsMouse ? 1.04 : 1

        Behavior on width {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            ScaleAnimator { duration: 160; easing.type: Easing.OutCubic }
        }

        Loader {
            id: content

            anchors.centerIn: parent
            sourceComponent: [area.vertical ? columnVertical : columnHorizontal,
                              area.vertical ? rowVertical : rowHorizontal,
                              area.vertical ? gridVertical : gridHorizontal,
                              area.vertical ? analogVertical : analogHorizontal][area.layout] ?? columnVertical

            // A new layout fades in while the plate takes its size
            onLoaded: fadeIn.restart()

            OpacityAnimator on opacity {
                id: fadeIn

                from: 0
                to: 1
                duration: 220
                easing.type: Easing.OutCubic
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

    // --- Layouts ---

    // 0 Column, vertical: hours above minutes, the icons below one another
    Component {
        id: columnVertical

        Column {
            spacing: 10

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -4

                TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.hours; size: 22 }
                TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.minutes; size: 22 }
            }

            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 1; spacing: 8 }
        }
    }

    // 0 Column, horizontal: one line
    Component {
        id: columnHorizontal

        Row {
            spacing: 10

            TimeText { anchors.verticalCenter: parent.verticalCenter; text: d.time; size: 15 }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 3; spacing: 8 }
        }
    }

    // 1 Row, vertical: the time in one line, the icons in a row below
    Component {
        id: rowVertical

        Column {
            spacing: 8

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 17 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // 1 Row, horizontal: the time above the icons, narrower than one line
    Component {
        id: rowHorizontal

        Column {
            spacing: 4

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 16 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // 2 Grid, vertical: the time, four icons in two rows below
    Component {
        id: gridVertical

        Column {
            spacing: 8

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 17 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 2; spacing: 8; withBluetooth: true }
        }
    }

    // 2 Grid, horizontal: the time, the grid next to it
    Component {
        id: gridHorizontal

        Row {
            spacing: 12

            TimeText { anchors.verticalCenter: parent.verticalCenter; text: d.time; size: 17 }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 2; spacing: 6; withBluetooth: true }
        }
    }

    // 3 Analog, vertical: the clock face, the icons in a row below
    Component {
        id: analogVertical

        Column {
            spacing: 8

            AnalogClock { anchors.horizontalCenter: parent.horizontalCenter; width: 44; height: 44; time: d.now }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // 3 Analog, horizontal: the clock face, the icons next to it
    Component {
        id: analogHorizontal

        Row {
            spacing: 10

            AnalogClock { anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; time: d.now }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 3; spacing: 8 }
        }
    }

    // --- Parts ---

    component TimeText: Text {
        property real size: 15

        color: Theme.label
        font.pixelSize: size
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }

    // The status icons in a grid of the given number of columns
    component Indicators: Grid {
        id: indicators

        property bool withBluetooth: false

        Repeater {
            model: indicators.withBluetooth ? d.indicatorsWithBluetooth : d.indicators

            Kirigami.Icon {
                required property string modelData

                width: 16
                height: 16
                source: modelData
                isMask: true
                color: Theme.label
            }
        }
    }

    QtObject {
        id: d

        property date now: new Date()
        readonly property string hours: Qt.formatTime(now, "HH")
        readonly property string minutes: Qt.formatTime(now, "mm")
        readonly property string time: hours + ":" + minutes

        readonly property var indicators: area.controlCenter
                                          ? [area.controlCenter.wifiIcon, area.controlCenter.volumeIcon,
                                             area.controlCenter.batteryIcon]
                                          : []
        readonly property var indicatorsWithBluetooth: area.controlCenter
                                                       ? [area.controlCenter.wifiIcon, area.controlCenter.bluetoothIcon,
                                                          area.controlCenter.volumeIcon, area.controlCenter.batteryIcon]
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
