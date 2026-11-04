pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Maia.Network as Network
import LumenFrontend

// The Wi-Fi page of quick settings, as in Windows 11: a back arrow, the Wi-Fi switch, the networks
// in reach and "More Wi-Fi settings". A click on a network opens its actions in its row (one row at
// a time): Connect, or Disconnect for the connected one. The password is asked in the same row
// when NetworkManager needs it (Shell.wifiPrompt), with "Next" enabled only for a valid password,
// so the user never leaves the list. Failures are told in a line above the list, in words.
//
// Data: the Maia network service through Maia.Network (WifiStatus is Shell.wifi).
ColumnLayout {
    id: page

    // The page is shown: scanning runs only meanwhile (as GNOME: at once, then every 15 s)
    property bool shown: false

    signal backRequested()

    // The network whose actions are open
    property string expandedId: ""
    // The last failure, in words; cleared when the user tries again
    property string failure: ""

    readonly property Network.WifiStatus wifi: Shell.wifi
    readonly property Network.SecretPrompt prompt: Shell.wifiPrompt

    spacing: Theme.spacingM

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
            page.expandedId = ""
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

    // --- Header ---

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS

        SubtleButton {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            padding: 0
            Accessible.name: qsTr("Back")
            onClicked: page.backRequested()
            contentItem: Item {
                LIcon { anchors.centerIn: parent; size: 16; iconName: "go-previous-symbolic" }
            }
        }

        LText {
            Layout.fillWidth: true
            text: qsTr("Wi-Fi")
            font.pixelSize: Theme.fontBodyLarge
            font.weight: Font.DemiBold
        }

        // Scanning: a short sweeping bar, as the Windows 11 list shows it
        Item {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 4
            clip: true
            visible: page.wifi.scanning
            Accessible.name: qsTr("Searching for networks")

            Rectangle {
                width: 12
                height: parent.height
                radius: 2
                color: Theme.accent

                SequentialAnimation on x {
                    running: page.wifi.scanning
                    loops: Animation.Infinite
                    NumberAnimation { from: -12; to: 28; duration: 900; easing.type: Easing.InOutSine }
                }
            }
        }

        LSwitch {
            checked: page.wifi.enabled
            enabled: page.wifi.canToggle
            Accessible.name: qsTr("Wi-Fi")
            onToggled: page.wifi.setEnabled(checked)
        }
    }

    // --- What is wrong, if anything ---

    LText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.textSecondary
        visible: text.length > 0
        text: !page.wifi.available ? qsTr("Wi-Fi is unavailable: the network service is not running.")
            : !page.wifi.hasDevice ? qsTr("No Wi-Fi adapter was found.")
            : !page.wifi.hardwareEnabled ? qsTr("Wi-Fi is turned off with a switch on this computer.")
            : !page.wifi.enabled ? qsTr("Wi-Fi is off.")
            : ""
    }

    LText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.critical
        visible: page.failure.length > 0
        text: page.failure
    }

    // A captive portal: the internet works after signing in
    Card {
        Layout.fillWidth: true
        Layout.preferredHeight: portalColumn.implicitHeight + 2 * Theme.spacingM
        visible: page.wifi.portal

        ColumnLayout {
            id: portalColumn

            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            LText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("Sign in to %1 to use the internet.").arg(page.wifi.networkName)
            }
            RowLayout {
                spacing: Theme.spacingS
                AccentButton {
                    text: qsTr("Open sign-in page")
                    onClicked: page.wifi.openPortal()
                }
                SubtleButton {
                    Accessible.name: qsTr("Check again")
                    onClicked: page.wifi.checkConnectivity()
                    contentItem: LText { text: qsTr("Check again") }
                }
            }
        }
    }

    // --- Networks ---

    ListView {
        id: list

        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 360)
        visible: page.wifi.enabled && count > 0
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2

        model: Network.WifiNetworksModel { id: networks }

        // Rows slide to their new place when the order changes (a network connected, signals moved)
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.durationNormal; easing.type: Theme.easingStandard }
        }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
        }

        delegate: NetworkRow {}
    }

    LText {
        Layout.fillWidth: true
        visible: page.wifi.enabled && page.wifi.hasDevice && list.count === 0
        color: Theme.textSecondary
        text: qsTr("Searching for networks…")
    }

    // A password for a network that is not in the list (a hidden one)
    PasswordForm {
        Layout.fillWidth: true
        visible: page.prompt.pending && !page.listHasPromptedNetwork()
    }

    // --- Footer ---

    SubtleButton {
        Layout.fillWidth: true
        Accessible.name: qsTr("More Wi-Fi settings")
        onClicked: Shell.launch("systemsettings kcm_networkmanagement")
        contentItem: LText { text: qsTr("More Wi-Fi settings") }
    }

    function listHasPromptedNetwork() {
        for (let i = 0; i < list.count; ++i) {
            if (networks.data(networks.index(i, 0), Network.WifiNetworksModel.NameRole) === page.prompt.name)
                return true
        }
        return false
    }

    // The fields of the pending password request, with Next and Cancel
    component PasswordForm: ColumnLayout {
        id: form

        spacing: Theme.spacingS

        property var values: []

        function valid() {
            const fields = page.prompt.fields
            for (let i = 0; i < fields.length; ++i) {
                if (!page.prompt.valid(i, values[i] ?? ""))
                    return false
            }
            return fields.length > 0
        }

        LText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: page.prompt.retry ? qsTr("That didn't work. Enter the network security key again")
                                    : qsTr("Enter the network security key")
            color: page.prompt.retry ? Theme.critical : Theme.textPrimary
        }

        Repeater {
            model: page.prompt.fields

            PasswordField {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                hidden: modelData.hidden
                text: modelData.value
                placeholderText: modelData.key === Network.Network.SecretKey.EapIdentity ? qsTr("User name") : qsTr("Password")
                Component.onCompleted: {
                    if (index === 0)
                        forceActiveFocus()
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

        LText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: page.prompt.wpsPushButton
            color: Theme.textSecondary
            font.pixelSize: Theme.fontCaption
            text: qsTr("You can also connect by pressing the WPS button on the router.")
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spacingS

            SubtleButton {
                Accessible.name: qsTr("Cancel")
                onClicked: page.prompt.cancel()
                contentItem: LText { text: qsTr("Cancel") }
            }
            AccentButton {
                text: qsTr("Next")
                enabled: form.valid()
                opacity: enabled ? 1 : 0.5
                onClicked: page.prompt.answer(form.values)
            }
        }
    }

    // One network: signal and padlock, name, state; its actions when open
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
        readonly property bool expanded: page.expandedId === networkId || prompted

        width: ListView.view.width
        height: column.implicitHeight + 2 * Theme.spacingS
        radius: Theme.radiusSmall
        color: active ? Theme.selection : rowArea.containsMouse || expanded ? Theme.subtleHover : "transparent"

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        Behavior on height { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }

        Accessible.role: Accessible.ListItem
        Accessible.name: name + ", " + (secure ? qsTr("Secured") : qsTr("Open"))

        MouseArea {
            id: rowArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: page.expandedId = row.expanded && !row.prompted ? "" : row.networkId
        }

        ColumnLayout {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                Item {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20

                    LIcon {
                        anchors.centerIn: parent
                        size: 20
                        iconName: "network-wireless-signal-" + ["none", "weak", "ok", "good", "excellent"][row.signalLevel] + "-symbolic"
                    }
                    LIcon {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -3
                        size: 10
                        iconName: "lock-symbolic"
                        visible: row.secure
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    LText {
                        Layout.fillWidth: true
                        text: row.name
                        elide: Text.ElideRight
                    }
                    LText {
                        Layout.fillWidth: true
                        font.pixelSize: Theme.fontCaption
                        color: Theme.textSecondary
                        text: row.connecting ? qsTr("Connecting…")
                            : row.active ? (row.secure ? qsTr("Connected, secured") : qsTr("Connected"))
                            : row.secure ? qsTr("Secured") : qsTr("Open")
                    }
                }
            }

            // Actions of the open row
            PasswordForm {
                Layout.fillWidth: true
                Layout.leftMargin: 20 + Theme.spacingM
                visible: row.prompted
            }

            RowLayout {
                Layout.fillWidth: true
                visible: row.expanded && !row.prompted

                Item { Layout.fillWidth: true }

                SubtleButton {
                    visible: row.active
                    Accessible.name: qsTr("Disconnect")
                    onClicked: devices.disconnectDevice(row.deviceId)
                    contentItem: LText { text: qsTr("Disconnect") }
                }
                AccentButton {
                    visible: !row.active
                    text: qsTr("Connect")
                    onClicked: {
                        page.failure = ""
                        networks.connectNetwork(row.networkId, result => {
                            if (result.error === Network.Network.ErrorCode.InvalidArgument && row.enterprise)
                                page.failure = qsTr("%1 needs sign-in details. Set it up in Wi-Fi settings.").arg(row.name)
                            else if (!result.ok)
                                page.failure = qsTr("Can't connect to %1.").arg(row.name)
                        })
                    }
                }
            }
        }
    }
}
