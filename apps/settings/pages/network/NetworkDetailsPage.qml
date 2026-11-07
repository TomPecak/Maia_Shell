import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// Settings › Wi-Fi › <network> (docs #10, #12, #13, #17, #18, #23 - #25): facts about the
// connection, then its settings in tabs. Changes wait for "Save" (several fields belong together,
// e.g. a manual address and its gateway); "Revert" undoes them. Leaving with unsaved changes asks.
SettingsPage {
    id: page

    required property string uuid
    property string deviceId
    property string networkId

    title: profile.name || qsTr("Network")

    // The profile as saved, and the edited copy
    property var original: null
    property var edited: null
    property int revision
    property int loaded
    property bool saving: false
    property string loadError
    property string saveError

    readonly property bool dirty: revision >= 0 && edited !== null && (!Texts.same(edited, original) || securityForm.secrets().length > 0)
    readonly property bool valid: revision >= 0 && edited !== null && edited.name.trim().length > 0 && identityValid
                                  && ip4Form.valid && ip6Form.valid && securityForm.valid
    readonly property bool identityValid: {
        if (revision < 0 || !edited)
            return false
        const w = edited.wifi
        return w.ssid.length > 0 && Texts.utf8Length(w.ssid) <= 32
               && (w.bssid.length === 0 || NetworkControl.isValidMac(w.bssid))
               && (w.macAddress.length === 0 || NetworkControl.isValidMac(w.macAddress))
               && (w.clonedMac !== Network.ClonedMac.Address || NetworkControl.isValidMac(w.clonedMacAddress))
    }

    // The models change in place: a counter makes the values below follow them
    property int modelRevision
    readonly property var profile: modelRevision >= 0 ? saved.get(uuid) : ({})
    readonly property var device: modelRevision >= 0 ? devices.get(profile.activeDeviceId || deviceId) : ({})
    readonly property var network: modelRevision >= 0 && networkId.length > 0 ? networks.get(networkId) : ({})
    readonly property bool connected: profile.active === true

    SavedNetworksModel {
        id: saved
        onDataChanged: ++page.modelRevision
        onCountChanged: ++page.modelRevision
    }
    WifiDevicesModel {
        id: devices
        onDataChanged: ++page.modelRevision
        onCountChanged: ++page.modelRevision
    }
    WifiNetworksModel {
        id: networks
        onDataChanged: ++page.modelRevision
        onCountChanged: ++page.modelRevision
    }

    function load() {
        NetworkControl.settings(uuid, (result, settings) => {
            if (!result.ok) {
                page.loadError = Texts.error(result)
                return
            }
            page.original = settings
            page.revert()
        })
    }

    function revert() {
        edited = Texts.clone(original)
        securityForm.password = ""
        securityForm.wepKey = ""
        securityForm.leapPassword = ""
        ++loaded
        ++revision
        saveError = ""
    }

    function save() {
        saving = true
        saveError = ""
        NetworkControl.updateSettings(uuid, edited, securityForm.secrets(), result => {
            saving = false
            if (!result.ok) {
                saveError = Texts.error(result)
                return
            }
            SettingsApp.toast(qsTr("Saved"))
            load()
        })
    }

    // maia-settings --action details:<tab index> (testing)
    property int initialTab: 0

    Component.onCompleted: {
        tabs.currentIndex = initialTab
        load()
    }

    InfoBar {
        visible: page.loadError.length > 0
        severity: "error"
        title: qsTr("The settings cannot be read")
        message: page.loadError
    }

    SelectorBar {
        id: tabs
        model: [qsTr("Details"), qsTr("Identity"), qsTr("IPv4"), qsTr("IPv6"), qsTr("Security")]
    }

    // --- Details ---

    SettingsGroup {
        visible: tabs.currentIndex === 0
        title: page.connected ? qsTr("Connection") : ""

        Repeater {
            model: {
                const rows = []
                const d = page.device
                const n = page.network
                if (page.connected && d && d.deviceId) {
                    if (n.signalLevel !== undefined)
                        rows.push([qsTr("Signal strength"), Texts.signalText(n.signalLevel) + " (" + n.strength + " %)"])
                    rows.push([qsTr("Link speed"), [Texts.speed(d.bitrate), Texts.band(n.frequency || 0)].filter(s => s).join(" · ")])
                    rows.push([qsTr("Security"), Texts.security(page.profile.security)])
                    rows.push([qsTr("IPv4 address"), (d.ip4Addresses || []).join(", ")])
                    rows.push([qsTr("IPv6 address"), (d.ip6Addresses || []).join(", ")])
                    rows.push([qsTr("Default route"), [d.ip4Gateway, d.ip6Gateway].filter(s => s).join(", ")])
                    rows.push([qsTr("DNS"), (d.ip4Dns || []).concat(d.ip6Dns || []).join(", ")])
                }
                if (d && d.deviceId) {
                    rows.push([qsTr("Hardware address"), d.hwAddress])
                    rows.push([qsTr("Supported frequencies"), Texts.bands(d.bands)])
                }
                if (!page.connected)
                    rows.push([qsTr("Last used"), Texts.lastUsed(page.profile.lastUsed)])
                return rows.filter(r => r[1] && r[1].length > 0)
            }

            SettingsCard {
                required property var modelData

                title: modelData[0]

                LText {
                    text: modelData[1]
                    color: Theme.textSecondary
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, 420)
                }
            }
        }
    }

    SettingsGroup {
        visible: tabs.currentIndex === 0 && page.edited !== null
        title: qsTr("Settings")

        SettingsCard {
            title: qsTr("Connect automatically")
            description: qsTr("When the network is in reach")

            LSwitch {
                checked: page.revision >= 0 && page.edited ? page.edited.autoconnect : true
                Accessible.name: qsTr("Connect automatically")
                onToggled: { page.edited.autoconnect = checked; ++page.revision }
            }
        }

        SettingsCard {
            title: qsTr("Available to all users")
            description: NetworkControl.canEditForAll ? qsTr("Others who use this computer can connect to it too")
                                                      : qsTr("The system policy does not allow it")
            enabled: NetworkControl.canEditForAll

            LSwitch {
                checked: page.revision >= 0 && page.edited ? page.edited.availableToAll : false
                Accessible.name: qsTr("Available to all users")
                onToggled: { page.edited.availableToAll = checked; ++page.revision }
            }
        }

        SettingsCard {
            title: qsTr("Metered connection")
            description: qsTr("Has data limits or costs: software updates and other large downloads do not start by themselves")

            ComboField {
                implicitWidth: 180
                model: [{ text: qsTr("Automatic"), value: Network.Metered.Unknown }, { text: qsTr("Yes"), value: Network.Metered.Yes },
                        { text: qsTr("No"), value: Network.Metered.No }]
                currentIndex: page.revision >= 0 && page.edited ? Math.max(0, indexOfValue(page.edited.metered)) : 0
                onActivated: { page.edited.metered = currentValue; ++page.revision }
            }
        }

        SettingsCard {
            title: qsTr("Forget this network")
            description: qsTr("Its password and settings are deleted")

            StandardButton {
                text: qsTr("Forget…")
                destructive: true
                onClicked: forgetDialog.open()
            }
        }
    }

    // --- Identity ---

    ColumnLayout {
        visible: tabs.currentIndex === 1 && page.edited !== null
        spacing: Theme.spacingL
        Layout.fillWidth: true

        FormField {
            label: qsTr("Name")

            PasswordField {
                hidden: false
                text: page.loaded >= 0 && page.edited ? page.edited.name : ""
                Layout.fillWidth: true
                onTextEdited: { page.edited.name = text; ++page.revision }
            }
        }

        FormField {
            label: qsTr("Network name (SSID)")
            error: page.revision >= 0 && page.edited && Texts.utf8Length(page.edited.wifi.ssid) > 32 ? qsTr("A network name has at most 32 bytes.") : ""

            PasswordField {
                hidden: false
                text: page.loaded >= 0 && page.edited ? page.edited.wifi.ssid : ""
                Layout.fillWidth: true
                onTextEdited: { page.edited.wifi.ssid = text; ++page.revision }
            }
        }

        SettingsCard {
            title: qsTr("Hidden network")
            description: qsTr("The network does not show its name: this computer looks for it")

            LSwitch {
                checked: page.revision >= 0 && page.edited ? page.edited.wifi.hidden : false
                Accessible.name: qsTr("Hidden network")
                onToggled: { page.edited.wifi.hidden = checked; ++page.revision }
            }
        }

        FormField {
            label: qsTr("Access point (BSSID)")
            help: qsTr("Connect only through this access point. Empty: any.")
            error: page.revision >= 0 && page.edited && page.edited.wifi.bssid.length > 0 && !NetworkControl.isValidMac(page.edited.wifi.bssid)
                   ? qsTr("Not a valid address (00:11:22:33:44:55)") : ""

            PasswordField {
                hidden: false
                text: page.loaded >= 0 && page.edited ? page.edited.wifi.bssid : ""
                placeholderText: "00:11:22:33:44:55"
                Layout.fillWidth: true
                onTextEdited: { page.edited.wifi.bssid = text.trim(); ++page.revision }
            }
        }

        FormField {
            label: qsTr("Adapter (MAC address)")
            help: qsTr("Use this network only with this Wi-Fi adapter. Empty: any.")
            error: page.revision >= 0 && page.edited && page.edited.wifi.macAddress.length > 0 && !NetworkControl.isValidMac(page.edited.wifi.macAddress)
                   ? qsTr("Not a valid address (00:11:22:33:44:55)") : ""

            PasswordField {
                hidden: false
                text: page.loaded >= 0 && page.edited ? page.edited.wifi.macAddress : ""
                placeholderText: page.device ? page.device.permHwAddress || "" : ""
                Layout.fillWidth: true
                onTextEdited: { page.edited.wifi.macAddress = text.trim(); ++page.revision }
            }
        }

        FormField {
            label: qsTr("Cloned MAC address")
            help: qsTr("The address the network sees. A random one per network makes this computer harder to follow.")

            ComboField {
                Layout.fillWidth: true
                model: [{ text: qsTr("Default"), value: Network.ClonedMac.Default },
                        { text: qsTr("Random"), value: Network.ClonedMac.Random },
                        { text: qsTr("Stable"), value: Network.ClonedMac.Stable },
                        { text: qsTr("Stable for this network"), value: Network.ClonedMac.StableSsid },
                        { text: qsTr("Permanent (the adapter's own)"), value: Network.ClonedMac.Permanent },
                        { text: qsTr("Preserve"), value: Network.ClonedMac.Preserve },
                        { text: qsTr("This address…"), value: Network.ClonedMac.Address }]
                currentIndex: page.revision >= 0 && page.edited ? Math.max(0, indexOfValue(page.edited.wifi.clonedMac)) : 0
                onActivated: { page.edited.wifi.clonedMac = currentValue; ++page.revision }
            }
        }

        FormField {
            visible: page.revision >= 0 && page.edited && page.edited.wifi.clonedMac === Network.ClonedMac.Address
            label: qsTr("Address")
            error: page.revision >= 0 && page.edited && page.edited.wifi.clonedMacAddress.length > 0 && !NetworkControl.isValidMac(page.edited.wifi.clonedMacAddress)
                   ? qsTr("Not a valid address (00:11:22:33:44:55)") : ""

            PasswordField {
                hidden: false
                text: page.loaded >= 0 && page.edited ? page.edited.wifi.clonedMacAddress : ""
                placeholderText: "00:11:22:33:44:55"
                Layout.fillWidth: true
                onTextEdited: { page.edited.wifi.clonedMacAddress = text.trim(); ++page.revision }
            }
        }
    }

    // --- IPv4, IPv6 ---

    IpSettingsForm {
        id: ip4Form

        visible: tabs.currentIndex === 2 && page.edited !== null
        ip: page.edited ? page.edited.ip4 : null
        revision: page.revision
        loaded: page.loaded
        onEdited: ++page.revision
        onRestructured: { ++page.loaded; ++page.revision }
    }

    IpSettingsForm {
        id: ip6Form

        visible: tabs.currentIndex === 3 && page.edited !== null
        ip6: true
        ip: page.edited ? page.edited.ip6 : null
        revision: page.revision
        loaded: page.loaded
        onEdited: ++page.revision
        onRestructured: { ++page.loaded; ++page.revision }
    }

    // --- Security ---

    SecurityForm {
        id: securityForm

        visible: tabs.currentIndex === 4 && page.edited !== null
        security: page.edited ? page.edited.security : null
        revision: page.revision
        loaded: page.loaded
        editing: true
        canLoadSecrets: true
        onEdited: ++page.revision
        onLoadSecretsRequested: {
            NetworkControl.secrets(page.uuid, (result, secrets) => {
                if (result.ok)
                    securityForm.showSecrets(secrets)
                else
                    page.saveError = Texts.error(result)
                ++page.revision
            })
        }
    }

    // --- Save / Revert: at the end of the page, where one is after the changes ---

    InfoBar {
        visible: page.saveError.length > 0
        severity: "error"
        title: qsTr("Not saved")
        message: page.saveError
    }

    RowLayout {
        visible: page.edited !== null
        spacing: Theme.spacingS
        Layout.fillWidth: true

        ProgressRing {
            visible: page.saving
            implicitWidth: 20
            implicitHeight: 20
            value: 0.25
            RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: page.saving }
        }

        LText {
            visible: page.dirty && !page.valid
            text: qsTr("Some details are missing or not valid.")
            color: Theme.critical
        }

        Item { Layout.fillWidth: true }

        StandardButton {
            text: qsTr("Revert")
            enabled: page.dirty && !page.saving
            onClicked: page.revert()
        }

        AccentButton {
            text: qsTr("Save")
            enabled: page.dirty && page.valid && !page.saving
            opacity: enabled ? 1 : 0.45
            Layout.preferredWidth: Math.max(implicitWidth, 120)
            onClicked: page.save()
        }
    }

    ContentDialog {
        id: forgetDialog

        title: qsTr("Forget “%1”?").arg(page.profile.name || "")
        primaryText: qsTr("Forget")
        onAccepted: {
            busy = true
            saved.forget(page.uuid, result => {
                busy = false
                if (result.ok) {
                    close()
                    SettingsApp.pop()
                    SettingsApp.toast(qsTr("Network forgotten"))
                } else {
                    error = Texts.error(result)
                }
            })
        }

        LText {
            text: qsTr("Its password and all its settings are deleted. To use it again you need the password.")
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
