import QtQuick

import Maia.Notifications.Center

import MaiaFrontend

import "../notifications"

// Do Not Disturb in the Control Center: the whole tile turns it on and off (until it is turned off);
// the two short choices beside it turn it on for a while, the way it is mostly wanted. Says why it is
// quiet when an application asked for it (a presentation).
ModulePlatter {
    id: tile

    property url icon

    readonly property bool on: NotificationCenter.doNotDisturb
    readonly property bool hasEnd: on && !isNaN(NotificationCenter.doNotDisturbUntil.getTime())
    readonly property string inhibitor: NotificationCenter.inhibitors.length > 0
                                        ? NotificationCenter.inhibitors[0].appName : ""

    // Minutes to tomorrow morning, 7:00
    function minutesToMorning() {
        const now = new Date()
        const morning = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (now.getHours() < 7 ? 0 : 1), 7)
        return Math.ceil((morning.getTime() - now.getTime()) / 60000)
    }

    highlighted: area.containsMouse

    Accessible.role: Accessible.CheckBox
    Accessible.name: qsTr("Do Not Disturb")
    Accessible.description: state.text
    Accessible.checkable: true
    Accessible.checked: on
    Accessible.onPressAction: NotificationCenter.doNotDisturb = !tile.on

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: NotificationCenter.doNotDisturb = !tile.on
    }

    RoundToggle {
        id: circle

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: tile.icon
        onColor: Theme.indigo
        checked: tile.on
        interactive: false
        hovered: tile.highlighted
    }

    Column {
        anchors.left: circle.right
        anchors.leftMargin: 10
        anchors.right: durations.visible ? durations.left : parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: qsTr("Do Not Disturb")
            color: Theme.label
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            id: state

            width: parent.width
            text: tile.hasEnd ? qsTr("Until %1").arg(Qt.formatDateTime(NotificationCenter.doNotDisturbUntil,
                                                                       Qt.locale().timeFormat(Locale.ShortFormat)))
                : tile.on ? qsTr("On")
                : tile.inhibitor.length > 0 ? qsTr("Quiet for %1").arg(tile.inhibitor)
                : qsTr("Off")
            color: Theme.secondaryLabel
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    Row {
        id: durations

        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        visible: !tile.on

        NotificationButton {
            objectName: "dndOneHour"
            text: qsTr("1 h")
            sidePadding: 12
            fontSize: 13
            onClicked: NotificationCenter.setDoNotDisturbFor(60)
        }

        NotificationButton {
            objectName: "dndUntilMorning"
            text: qsTr("Until morning")
            sidePadding: 12
            fontSize: 13
            onClicked: NotificationCenter.setDoNotDisturbFor(tile.minutesToMorning())
        }
    }
}
