pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import org.kde.kirigami as Kirigami

import Maia.Network as Network
import MaiaFrontend

// The Wi-Fi details of the Control Center, in the place of the modules (iPadOS shows the networks
// in the Control Center too): back, the Wi-Fi switch, the networks in reach and "Wi-Fi Settings…".
//
// A click on a network joins it (as on iPadOS: no separate "Connect" step); the connected one
// shows a check mark and, under the pointer, "Disconnect". When NetworkManager needs a password,
// the network's row opens with the fields (a network not in the list, e.g. a hidden one, gets them
// at the top), so the user never leaves the list. Failures are told in a line above the list.
//
// Data: the Maia network service through Maia.Network (ControlCenterState.wifi, wifiPrompt).
ModulePlatter {
    id: page

    property ControlCenterState controlCenter
    // Shown: scanning runs only meanwhile (at once, then every 15 s, as GNOME)
    property bool shown: false

    signal backRequested()
    signal settingsRequested()

    readonly property Network.WifiStatus wifi: controlCenter.wifi
    readonly property Network.SecretPrompt prompt: controlCenter.wifiPrompt

    // The last failure, in words; cleared when the user tries again
    property string failure: ""

    implicitHeight: column.implicitHeight + 2 * 14

    function reasonText(reason) {
        switch (reason) {
        case Network.Network.StateReason.WrongSecrets:
            return qsTr("The password was not accepted.")
        case Network.Network.StateReason.SupplicantTimeout:
            return qsTr("The network did not answer in time.")
        case Network.Network.StateReason.IpConfigFailed:
        case Network.Network.StateReason.IpConfigExpired:
            return qsTr("The network did not give this computer an address.")
        case Network.Network.StateReason.SsidNotFound:
            return qsTr("The network is out of reach.")
        default:
            return qsTr("The connection failed.")
        }
    }

    Connections {
        target: page.wifi

        function onActivationFailed(name, reason) {
            page.failure = qsTr("Can't connect to %1. %2").arg(name).arg(page.reasonText(reason))
        }
        function onConnectedTo() {
            page.failure = ""
        }
    }

    Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        running: page.shown && page.wifi.enabled
        onTriggered: page.wifi.scan()
    }

    Network.WifiDevicesModel { id: devices }

    Column {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 10

        // --- Header: back, title, switch ---

        Item {
            width: parent.width
            height: 34

            Rectangle {
                id: back

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: backArea.pressed ? Theme.pressed : backArea.containsMouse ? Theme.hover : "transparent"

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Back")
                Accessible.onPressAction: page.backRequested()

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: Qt.resolvedUrl("../../assets/icons/go-previous-symbolic.svg")
                    isMask: true
                    color: Theme.label
                }

                MouseArea {
                    id: backArea

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: page.backRequested()
                }
            }

            Text {
                anchors.left: back.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Wi-Fi")
                color: Theme.label
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }

            Switch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: page.wifi.enabled
                enabled: page.wifi.canToggle
                onToggled: page.wifi.setEnabled(!page.wifi.enabled)
            }
        }

        // --- State and failures ---

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: text.length > 0
            color: Theme.secondaryLabel
            font.pixelSize: 13
            text: !page.wifi.available ? qsTr("Wi-Fi is unavailable: the network service is not running.")
                : !page.wifi.hasDevice ? qsTr("No Wi-Fi adapter was found.")
                : !page.wifi.hardwareEnabled ? qsTr("Wi-Fi is turned off with a switch on this computer.")
                : !page.wifi.enabled ? qsTr("Wi-Fi is off.")
                : ""
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: page.failure.length > 0
            color: Theme.red
            font.pixelSize: 13
            text: page.failure
        }

        // A password for a network that is not in the list (a hidden one)
        PasswordForm {
            width: parent.width
            visible: page.prompt.pending && !page.listHasPromptedNetwork()
        }

        // --- Networks ---

        ListView {
            id: list

            width: parent.width
            height: Math.min(contentHeight, 340)
            visible: page.wifi.enabled && count > 0
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2

            model: Network.WifiNetworksModel { id: networks }

            // Rows slide to their new place when the order changes (a network connected, signals moved)
            displaced: Transition {
                NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
            }

            delegate: NetworkRow {}

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
            }
        }

        Text {
            width: parent.width
            visible: page.wifi.enabled && page.wifi.hasDevice && list.count === 0
            color: Theme.secondaryLabel
            font.pixelSize: 13
            text: qsTr("Searching for networks…")
        }

        // --- Footer ---

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.separator
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 10
            color: settingsArea.pressed ? Theme.pressed : settingsArea.containsMouse ? Theme.hover : "transparent"

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Wi-Fi Settings…")
            Accessible.onPressAction: page.settingsRequested()

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Wi-Fi Settings…")
                color: Theme.label
                font.pixelSize: 14
            }

            MouseArea {
                id: settingsArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: page.settingsRequested()
            }
        }
    }

    function listHasPromptedNetwork() {
        for (let i = 0; i < list.count; ++i) {
            if (networks.data(networks.index(i, 0), Network.WifiNetworksModel.NameRole) === page.prompt.name)
                return true
        }
        return false
    }

    function join(networkId, name, enterprise) {
        page.failure = ""
        networks.connectNetwork(networkId, result => {
            if (result.error === Network.Network.ErrorCode.InvalidArgument && enterprise)
                page.failure = qsTr("%1 needs sign-in details. Set it up in Wi-Fi Settings.").arg(name)
            else if (!result.ok)
                page.failure = qsTr("Can't connect to %1.").arg(name)
        })
    }

    // --- Parts ---

    // The switch of iPadOS: green when on
    component Switch: Item {
        id: control

        property bool checked: false

        signal toggled()

        width: 46
        height: 28
        opacity: enabled ? 1 : 0.4

        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Wi-Fi")
        Accessible.checked: checked
        Accessible.onToggleAction: control.toggled()
        Accessible.onPressAction: control.toggled()

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: control.checked ? Theme.green : Theme.toggleOff

            Behavior on color {
                ColorAnimation { duration: 180 }
            }
        }

        Rectangle {
            x: control.checked ? control.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: "white"

            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: control.enabled
            onClicked: control.toggled()
        }
    }

    // The fields of the pending password request, with Join and Cancel
    component PasswordForm: Column {
        id: form

        property var values: []

        spacing: 8

        function valid() {
            const fields = page.prompt.fields
            for (let i = 0; i < fields.length; ++i) {
                if (!page.prompt.valid(i, values[i] ?? ""))
                    return false
            }
            return fields.length > 0
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: page.prompt.retry ? qsTr("That didn't work. Enter the password for “%1” again").arg(page.prompt.name)
                                    : qsTr("Enter the password for “%1”").arg(page.prompt.name)
            color: page.prompt.retry ? Theme.red : Theme.label
            font.pixelSize: 13
        }

        Repeater {
            model: page.prompt.fields

            PasswordField {
                required property var modelData
                required property int index

                width: form.width
                hidden: modelData.hidden
                text: modelData.value
                placeholderText: modelData.key === Network.Network.SecretKey.EapIdentity ? qsTr("User name") : qsTr("Password")
                Component.onCompleted: {
                    if (index === 0)
                        input.forceActiveFocus()
                    const v = form.values.slice()
                    v[index] = text
                    form.values = v
                }
                onTextChanged: {
                    const v = form.values.slice()
                    v[index] = text
                    form.values = v
                }
                onAccepted: if (form.valid()) page.prompt.answer(form.values)
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: page.prompt.wpsPushButton
            color: Theme.secondaryLabel
            font.pixelSize: 12
            text: qsTr("You can also connect by pressing the WPS button on the router.")
        }

        Row {
            anchors.right: parent.right
            spacing: 8

            TextButton {
                text: qsTr("Cancel")
                onClicked: page.prompt.cancel()
            }
            TextButton {
                text: qsTr("Join")
                prominent: true
                enabled: form.valid()
                onClicked: page.prompt.answer(form.values)
            }
        }
    }

    component TextButton: Rectangle {
        id: button

        property string text
        property bool prominent: false

        signal clicked()

        width: label.implicitWidth + 2 * 16
        height: 32
        radius: 16
        opacity: enabled ? 1 : 0.4
        color: prominent ? (buttonArea.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent)
                         : (buttonArea.pressed ? Theme.pressed : buttonArea.containsMouse ? Theme.secondaryFillHover : Theme.secondaryFill)

        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: if (enabled) button.clicked()

        Text {
            id: label

            anchors.centerIn: parent
            text: button.text
            color: button.prominent ? "white" : Theme.label
            font.pixelSize: 14
            font.weight: button.prominent ? Font.DemiBold : Font.Normal
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            onClicked: button.clicked()
        }
    }

    // One network: check mark when connected, name, padlock, signal; the password when asked for
    component NetworkRow: Rectangle {
        id: row

        required property string networkId
        required property string name
        required property string deviceId
        required property bool secure
        required property bool enterprise
        required property int signalLevel
        required property bool active
        required property bool connecting

        readonly property bool prompted: page.prompt.pending && page.prompt.name === name

        width: ListView.view ? ListView.view.width : 0
        height: header.height + (prompted ? form.height + 10 : 0)
        radius: 10
        color: rowArea.containsMouse && !prompted ? Theme.hover : "transparent"

        Accessible.role: Accessible.Button
        Accessible.name: name + (active ? ", " + qsTr("connected") : "")
        Accessible.onPressAction: if (!row.active) page.join(row.networkId, row.name, row.enterprise)

        Item {
            id: header

            width: parent.width
            height: 38

            MouseArea {
                id: rowArea

                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (!row.active && !row.connecting)
                        page.join(row.networkId, row.name, row.enterprise)
                }
            }

            Kirigami.Icon {
                id: check

                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                visible: row.active && !row.connecting
                source: Qt.resolvedUrl("../../assets/icons/checkmark-symbolic.svg")
                isMask: true
                color: Theme.accent
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.right: icons.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.name
                    color: Theme.label
                    font.pixelSize: 14
                    font.weight: row.active ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: row.connecting
                    text: qsTr("Connecting…")
                    color: Theme.secondaryLabel
                    font.pixelSize: 12
                }
            }

            Row {
                id: icons

                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // The connected network can be left; shown under the pointer only
                TextButton {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    visible: row.active && !row.connecting && rowArea.containsMouse
                    text: qsTr("Disconnect")
                    onClicked: devices.disconnectDevice(row.deviceId)
                }

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    visible: row.secure
                    source: Qt.resolvedUrl("../../assets/icons/lock-symbolic.svg")
                    isMask: true
                    color: Theme.secondaryLabel
                }

                Kirigami.Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    source: page.controlCenter.signalIcon(row.signalLevel)
                    isMask: true
                    color: Theme.label
                }
            }
        }

        PasswordForm {
            id: form

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            visible: row.prompted
        }
    }
}
