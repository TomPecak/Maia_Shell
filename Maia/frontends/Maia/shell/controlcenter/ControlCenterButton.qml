pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

import Maia.Backend as Maia
import MaiaFrontend
import ".."
import "../jobs"

// The status of the session in the dock strip, at the other end of the strip than the power button:
// the time and the state of Do Not Disturb, Wi-Fi, the volume and the battery, read at a glance. One plate, two
// targets, as the status bar of iPadOS: the time opens the notification center (with a badge of what
// is unread and a ring while something is being copied), the icons open the Control Center. Both unfold from this corner of the screen. The
// part under the pointer lights up, so the split can be seen before clicking. Moves with the dock
// like the power button (StripItem.qml).
//
// Layouts (being tried out, chosen with a module of the Control Center): each has a variant along a
// vertical strip (dock at the left or right, as narrow as the dock) and along a horizontal one.
//   grid     the default. Vertical: "14:37", Wi-Fi, Bluetooth, volume, battery in two rows below;
//            horizontal: the time, the grid next to it
//   column   vertical: hours above minutes, the icons below one another; horizontal: one line
//   row      vertical: "14:37", the icons in a row below; horizontal: the time above the icons
//   analog   a clock face, the icons in a row below it (vertical) or next to it (horizontal)
StripItem {
    id: area

    property ControlCenterState controlCenter
    // The Control Center is open (its part looks pressed meanwhile)
    property bool checked: false
    // The notification center is open (the same for the time)
    property bool notificationsChecked: false
    // Notifications not looked at yet
    property int unreadCount: 0
    // Jobs in progress and how far they are together (0 .. 100, -1 unknown): a ring by the clock
    property int jobsRunning: 0
    property int jobsPercent: -1
    // One of the layouts above, by name
    property string layout: "grid"

    // The icons
    signal clicked()
    // The time
    signal timeClicked()

    width: plate.width
    height: plate.height

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
        width: area.vertical ? (area.layout === "column" ? 56 : 72) : content.width + 2 * 16
        height: area.vertical ? content.height + 2 * 12 : content.height + 2 * (area.layout === "column" ? 13 : 9)
        radius: area.vertical ? 18 : (area.layout === "column" ? height / 2 : 18)
        color: Theme.dock
        border.width: 1
        border.color: Theme.hairline
        scale: timePart.pressed || statusPart.pressed ? 0.96 : timePart.hovered || statusPart.hovered ? 1.02 : 1

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

        // The part under the pointer, or of what is open
        Rectangle {
            readonly property var part: timePart.lit ? timePart : statusPart.lit ? statusPart : null
            readonly property bool held: part !== null && (part.pressed || part.checked)

            anchors.fill: parent
            anchors.leftMargin: part === statusPart && d.beside ? d.split : 3
            anchors.rightMargin: part === timePart && d.beside ? plate.width - d.split : 3
            anchors.topMargin: part === statusPart && !d.beside ? d.split : 3
            anchors.bottomMargin: part === timePart && !d.beside ? plate.height - d.split : 3
            radius: Math.max(4, plate.radius - 3)
            visible: part !== null
            color: held ? Theme.platePressed : Theme.plateHover

            Behavior on color {
                ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
            }
        }

        Loader {
            id: content

            anchors.centerIn: parent
            sourceComponent: area.layout === "column" ? (area.vertical ? columnVertical : columnHorizontal)
                           : area.layout === "row" ? (area.vertical ? rowVertical : rowHorizontal)
                           : area.layout === "analog" ? (area.vertical ? analogVertical : analogHorizontal)
                           : (area.vertical ? gridVertical : gridHorizontal)

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

    PlatePart {
        id: timePart

        x: plate.x
        y: plate.y
        width: d.beside ? d.split : plate.width
        height: d.beside ? plate.height : d.split
        checked: area.notificationsChecked
        Accessible.name: {
            const parts = [d.time, qsTr("notifications")]
            if (area.unreadCount > 0)
                parts.push(qsTr("%1 unread").arg(area.unreadCount))
            if (area.jobsRunning > 0)
                parts.push(area.jobsPercent >= 0 ? qsTr("task at %1 %").arg(area.jobsPercent) : qsTr("task running"))
            return parts.join(", ")
        }
        onClicked: area.timeClicked()
    }

    PlatePart {
        id: statusPart

        x: plate.x + (d.beside ? d.split : 0)
        y: plate.y + (d.beside ? 0 : d.split)
        width: d.beside ? plate.width - d.split : plate.width
        height: d.beside ? plate.height : plate.height - d.split
        checked: area.checked
        Accessible.name: area.controlCenter && area.controlCenter.quiet ? qsTr("Control Center, Do Not Disturb on")
                                                                        : qsTr("Control Center")
        onClicked: area.clicked()
    }

    Maia.MaskArea {
        anchors.fill: plate
    }

    // What is unread, on the corner of the time. Takes no input of its own
    Rectangle {
        objectName: "unreadBadge"
        x: plate.x - 6
        y: plate.y - 6
        width: Math.max(20, badgeText.implicitWidth + 10)
        height: 20
        radius: 10
        visible: area.unreadCount > 0 && !area.notificationsChecked
        color: Theme.red
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.5)

        Text {
            id: badgeText

            anchors.centerIn: parent
            text: area.unreadCount > 99 ? "99+" : area.unreadCount
            color: "white"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    // Something is being copied: on the other corner of the time than the badge. Takes no input
    Rectangle {
        objectName: "jobsRing"
        x: plate.x - 6
        y: plate.y + plate.height - height + 6
        width: 24
        height: 24
        radius: 12
        visible: area.jobsRunning > 0
        color: Theme.card
        border.width: 1
        border.color: Theme.hairline

        JobRing {
            anchors.centerIn: parent
            width: 18
            height: 18
            lineWidth: 2.5
            percent: area.jobsPercent
        }
    }

    // --- Layouts ---

    // Column, vertical: hours above minutes, the icons below one another
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

    // Column, horizontal: one line
    Component {
        id: columnHorizontal

        Row {
            spacing: 10

            TimeText { anchors.verticalCenter: parent.verticalCenter; text: d.time; size: 15 }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 3; spacing: 8; besideTime: true }
        }
    }

    // Row, vertical: the time in one line, the icons in a row below
    Component {
        id: rowVertical

        Column {
            spacing: 8

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 17 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // Row, horizontal: the time above the icons, narrower than one line
    Component {
        id: rowHorizontal

        Column {
            spacing: 4

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 16 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // Grid, vertical: the time, four icons in two rows below
    Component {
        id: gridVertical

        Column {
            spacing: 8

            TimeText { anchors.horizontalCenter: parent.horizontalCenter; text: d.time; size: 17 }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 2; spacing: 8; withBluetooth: true }
        }
    }

    // Grid, horizontal: the time, the grid next to it
    Component {
        id: gridHorizontal

        Row {
            spacing: 12

            TimeText { anchors.verticalCenter: parent.verticalCenter; text: d.time; size: 17 }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 2; spacing: 6; withBluetooth: true; besideTime: true }
        }
    }

    // Analog, vertical: the clock face, the icons in a row below
    Component {
        id: analogVertical

        Column {
            spacing: 8

            AnalogClock { anchors.horizontalCenter: parent.horizontalCenter; width: 44; height: 44; time: d.now }
            Indicators { anchors.horizontalCenter: parent.horizontalCenter; columns: 3; spacing: 6 }
        }
    }

    // Analog, horizontal: the clock face, the icons next to it
    Component {
        id: analogHorizontal

        Row {
            spacing: 10

            AnalogClock { anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; time: d.now }
            Indicators { anchors.verticalCenter: parent.verticalCenter; columns: 3; spacing: 8; besideTime: true }
        }
    }

    // --- Parts ---

    // One of the two targets of the plate
    component PlatePart: Item {
        id: part

        property bool checked: false
        readonly property bool pressed: partArea.pressed
        readonly property bool hovered: partArea.containsMouse
        readonly property bool lit: pressed || hovered || checked

        signal clicked()

        Accessible.role: Accessible.Button
        Accessible.onPressAction: part.clicked()

        MouseArea {
            id: partArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: part.clicked()
        }
    }

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
        // Beside the time (a row), or below it (a column)
        property bool besideTime: false

        Component.onCompleted: d.indicators_ = indicators
        Component.onDestruction: {
            if (d.indicators_ === indicators)
                d.indicators_ = null
        }

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

        // The icons of the layout shown now: where the plate divides between its two targets
        property Item indicators_: null
        readonly property bool beside: indicators_ !== null && indicators_.besideTime
        // Half way through the gap between the time and the icons, from the plate's start
        readonly property real split: {
            if (indicators_ === null)
                return (area.vertical ? plate.height : plate.width) / 2
            const gap = indicators_.parent.spacing / 2
            return beside ? content.x + indicators_.x - gap : content.y + indicators_.y - gap
        }

        property date now: new Date()
        readonly property string hours: Qt.formatTime(now, "HH")
        readonly property string minutes: Qt.formatTime(now, "mm")
        readonly property string time: hours + ":" + minutes

        // Without a battery (a desktop computer) its icon is "" and left out; Do Not Disturb comes
        // first, next to the time, while it is on
        readonly property var indicators: area.controlCenter
                                          ? [area.controlCenter.quietIcon, area.controlCenter.wifiIcon,
                                             area.controlCenter.volumeIcon, area.controlCenter.batteryIcon]
                                            .filter(icon => icon !== "")
                                          : []
        readonly property var indicatorsWithBluetooth: area.controlCenter
                                                       ? [area.controlCenter.quietIcon, area.controlCenter.wifiIcon,
                                                          area.controlCenter.bluetoothIcon, area.controlCenter.volumeIcon,
                                                          area.controlCenter.batteryIcon].filter(icon => icon !== "")
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
