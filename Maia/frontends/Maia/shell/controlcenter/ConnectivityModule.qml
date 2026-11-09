pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// The connections, together in one module (common region): Wi-Fi, Bluetooth, airplane mode. As
// in the Control Center of macOS, made for the pointer: the circle switches, the name next to it
// opens the details (the networks in reach for Wi-Fi), so both actions are one click and neither
// hides behind a long press.
ModulePlatter {
    id: module

    property ControlCenterState controlCenter

    // The network list was asked for (a click on "Wi-Fi")
    signal wifiDetailsRequested()

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        ToggleRow {
            title: qsTr("Wi-Fi")
            subtitle: module.controlCenter.wifiText
            icon: module.controlCenter.wifiIcon
            checked: module.controlCenter.wifi.enabled
            available: module.controlCenter.wifi.canToggle
            hasDetails: true
            onToggled: module.controlCenter.wifi.toggle()
            onDetailsRequested: module.wifiDetailsRequested()
        }

        ToggleRow {
            title: qsTr("Bluetooth")
            subtitle: module.controlCenter.bluetooth ? qsTr("On") : qsTr("Off")
            icon: module.controlCenter.icon("network-bluetooth-symbolic")
            checked: module.controlCenter.bluetooth
            onToggled: module.controlCenter.bluetooth = !module.controlCenter.bluetooth
        }

        ToggleRow {
            title: qsTr("Airplane Mode")
            subtitle: module.controlCenter.airplaneMode ? qsTr("On") : qsTr("Off")
            icon: module.controlCenter.icon("network-flightmode-on-symbolic")
            onColor: Theme.orange
            checked: module.controlCenter.airplaneMode
            onToggled: module.controlCenter.airplaneMode = !module.controlCenter.airplaneMode
        }
    }

    component ToggleRow: Item {
        id: row

        property string title
        property string subtitle
        property url icon
        property color onColor: Theme.blue
        property bool checked: false
        property bool available: true
        property bool hasDetails: false

        signal toggled()
        signal detailsRequested()

        width: parent ? parent.width : 0
        height: 44

        RoundToggle {
            id: circle

            anchors.verticalCenter: parent.verticalCenter
            size: 38
            icon: row.icon
            onColor: row.onColor
            checked: row.checked
            interactive: row.available
            opacity: row.available ? 1 : 0.4
            Accessible.name: row.title
            onClicked: row.toggled()
        }

        // The name: opens the details where there are any
        Rectangle {
            id: label

            anchors.left: circle.right
            anchors.leftMargin: 6
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 40
            radius: 12
            color: row.hasDetails && labelArea.containsMouse ? Theme.hover : "transparent"

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.right: chevron.left
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.title
                    color: Theme.label
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.subtitle
                    color: Theme.secondaryLabel
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Kirigami.Icon {
                id: chevron

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: row.hasDetails ? 14 : 0
                height: 14
                visible: row.hasDetails
                source: Qt.resolvedUrl("../../assets/icons/go-next-symbolic.svg")
                isMask: true
                color: Theme.secondaryLabel
            }

            MouseArea {
                id: labelArea

                anchors.fill: parent
                hoverEnabled: row.hasDetails
                cursorShape: row.hasDetails ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: row.hasDetails ? row.detailsRequested() : (row.available ? row.toggled() : undefined)
            }

            Accessible.role: row.hasDetails ? Accessible.Button : Accessible.NoRole
            Accessible.name: row.hasDetails ? qsTr("%1 details").arg(row.title) : ""
            Accessible.onPressAction: if (row.hasDetails) row.detailsRequested()
        }
    }
}
