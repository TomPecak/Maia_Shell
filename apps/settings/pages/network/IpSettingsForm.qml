import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

import "Texts.js" as Texts

// IPv4 or IPv6 settings of a profile (docs #23): the method, manual addresses and gateway, DNS,
// search domains, routes, "only for resources on its network". ip: the settings' ip4 or ip6
// object, changed in place.
ColumnLayout {
    id: form

    property var ip
    property bool ip6: false
    property int revision
    // Bumped when the settings are (re)loaded: the text fields take their values again
    property int loaded

    signal edited()
    // Rows were added or removed: the fields must be filled again
    signal restructured()

    readonly property int method: revision >= 0 && ip ? ip.method : Network.IpMethod.Auto
    readonly property bool manual: method === Network.IpMethod.Manual
    readonly property bool configured: method !== Network.IpMethod.Disabled && method !== Network.IpMethod.LinkLocal && method !== Network.IpMethod.Shared

    function validAddress(text) { return NetworkControl.isValidAddress(text, form.ip6) }

    readonly property bool valid: {
        if (revision < 0 || !ip)
            return false
        if (manual) {
            if (ip.addresses.length === 0)
                return false
            for (const a of ip.addresses) {
                if (!validAddress(a.address) || a.prefix < 1)
                    return false
            }
            if (ip.gateway.length > 0 && !validAddress(ip.gateway))
                return false
        }
        for (const d of ip.dns) {
            if (!validAddress(d))
                return false
        }
        for (const r of ip.routes) {
            if (!validAddress(r.destination) || r.prefix < 0 || (r.gateway.length > 0 && !validAddress(r.gateway)))
                return false
        }
        return true
    }

    function set(key, value) {
        ip[key] = value
        edited()
    }

    spacing: Theme.spacingL
    Layout.fillWidth: true

    FormField {
        label: form.ip6 ? qsTr("IPv6 method") : qsTr("IPv4 method")

        ComboField {
            Layout.fillWidth: true
            model: form.ip6
                   ? [{ text: qsTr("Automatic"), value: Network.IpMethod.Auto }, { text: qsTr("Automatic, DHCP only"), value: Network.IpMethod.DhcpOnly },
                      { text: qsTr("Manual"), value: Network.IpMethod.Manual }, { text: qsTr("Link-local only"), value: Network.IpMethod.LinkLocal },
                      { text: qsTr("Shared to other computers"), value: Network.IpMethod.Shared }, { text: qsTr("Disabled"), value: Network.IpMethod.Disabled }]
                   : [{ text: qsTr("Automatic (DHCP)"), value: Network.IpMethod.Auto }, { text: qsTr("Manual"), value: Network.IpMethod.Manual },
                      { text: qsTr("Link-local only"), value: Network.IpMethod.LinkLocal }, { text: qsTr("Shared to other computers"), value: Network.IpMethod.Shared },
                      { text: qsTr("Disabled"), value: Network.IpMethod.Disabled }]
            currentIndex: form.revision >= 0 ? Math.max(0, indexOfValue(form.method)) : 0
            onActivated: {
                form.set("method", currentValue)
                if (currentValue === Network.IpMethod.Manual && form.ip.addresses.length === 0) {
                    form.ip.addresses.push({ address: "", prefix: form.ip6 ? 64 : 24 })
                    form.restructured()
                }
            }
        }
    }

    // --- Manual addresses ---

    SettingsGroup {
        visible: form.manual
        title: qsTr("Addresses")

        Repeater {
            model: form.loaded >= 0 && form.ip ? form.ip.addresses.length : 0

            RowLayout {
                id: addressRow

                required property int index
                readonly property var entry: form.loaded >= 0 && form.ip && index < form.ip.addresses.length ? form.ip.addresses[index] : ({ address: "", prefix: 0 })

                spacing: Theme.spacingS
                Layout.fillWidth: true

                FormField {
                    label: qsTr("Address")
                    error: form.revision >= 0 && form.ip.addresses[addressRow.index] && form.ip.addresses[addressRow.index].address.length > 0 && !form.validAddress(form.ip.addresses[addressRow.index].address) ? qsTr("Not a valid address") : ""

                    PasswordField {
                        hidden: false
                        text: addressRow.entry.address
                        placeholderText: form.ip6 ? "fd00::10" : "192.168.1.10"
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.addresses[addressRow.index].address = text.trim()
                            form.edited()
                        }
                    }
                }

                FormField {
                    label: form.ip6 ? qsTr("Prefix") : qsTr("Netmask")
                    Layout.preferredWidth: 160
                    Layout.fillWidth: false
                    error: form.revision >= 0 && form.ip.addresses[addressRow.index] && form.ip.addresses[addressRow.index].prefix < 1 ? qsTr("Not valid") : ""

                    PasswordField {
                        hidden: false
                        text: addressRow.entry.prefix > 0 ? String(addressRow.entry.prefix) : ""
                        placeholderText: form.ip6 ? "64" : "24 / 255.255.255.0"
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.addresses[addressRow.index].prefix = Texts.prefixOf(text, form.ip6)
                            form.edited()
                        }
                    }
                }

                IconButton {
                    iconName: "user-trash-symbolic"
                    tip: qsTr("Remove this address")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        form.ip.addresses.splice(addressRow.index, 1)
                        form.restructured()
                    }
                }
            }
        }

        StandardButton {
            text: qsTr("Add address")
            iconName: "list-add-symbolic"
            onClicked: {
                form.ip.addresses.push({ address: "", prefix: form.ip6 ? 64 : 24 })
                form.restructured()
            }
        }
    }

    FormField {
        visible: form.manual
        label: qsTr("Gateway")
        error: form.revision >= 0 && form.ip && form.ip.gateway.length > 0 && !form.validAddress(form.ip.gateway) ? qsTr("Not a valid address") : ""

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.ip ? form.ip.gateway : ""
            placeholderText: form.ip6 ? "fd00::1" : "192.168.1.1"
            Layout.fillWidth: true
            onTextEdited: form.set("gateway", text.trim())
        }
    }

    // --- DNS ---

    SettingsGroup {
        visible: form.configured
        title: qsTr("DNS")

        SettingsCard {
            title: qsTr("Automatic DNS")
            description: qsTr("Use the servers the network offers")

            LSwitch {
                checked: form.revision >= 0 && form.ip ? form.ip.autoDns : true
                Accessible.name: qsTr("Automatic DNS")
                onToggled: form.set("autoDns", checked)
            }
        }
    }

    FormField {
        visible: form.configured
        label: qsTr("DNS servers")
        help: form.revision >= 0 && form.ip && form.ip.autoDns ? qsTr("Used besides the automatic ones. Separate them with commas.")
                                                               : qsTr("Separate them with commas.")
        error: {
            if (form.revision < 0 || !form.ip)
                return ""
            const bad = form.ip.dns.filter(d => !form.validAddress(d))
            return bad.length > 0 ? qsTr("Not a valid address: %1").arg(bad.join(", ")) : ""
        }

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.ip ? form.ip.dns.join(", ") : ""
            placeholderText: form.ip6 ? "2606:4700:4700::1111" : "1.1.1.1, 9.9.9.9"
            Layout.fillWidth: true
            onTextEdited: form.set("dns", Texts.list(text))
        }
    }

    FormField {
        visible: form.configured
        label: qsTr("Search domains")
        help: qsTr("Short names are looked up in these domains. Separate them with commas.")

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.ip ? form.ip.dnsSearch.join(", ") : ""
            placeholderText: "example.com"
            Layout.fillWidth: true
            onTextEdited: form.set("dnsSearch", Texts.list(text))
        }
    }

    // --- Routes ---

    SettingsGroup {
        visible: form.configured
        title: qsTr("Routes")

        SettingsCard {
            title: qsTr("Automatic routes")
            description: qsTr("Use the routes the network offers")

            LSwitch {
                checked: form.revision >= 0 && form.ip ? form.ip.autoRoutes : true
                Accessible.name: qsTr("Automatic routes")
                onToggled: form.set("autoRoutes", checked)
            }
        }

        Repeater {
            model: form.loaded >= 0 && form.ip ? form.ip.routes.length : 0

            RowLayout {
                id: routeRow

                required property int index
                readonly property var entry: form.loaded >= 0 && form.ip && index < form.ip.routes.length ? form.ip.routes[index]
                                                                                                           : ({ destination: "", prefix: 0, gateway: "", metric: -1 })

                spacing: Theme.spacingS
                Layout.fillWidth: true

                FormField {
                    label: qsTr("Destination")
                    error: form.revision >= 0 && form.ip.routes[routeRow.index] && form.ip.routes[routeRow.index].destination.length > 0 && !form.validAddress(form.ip.routes[routeRow.index].destination) ? qsTr("Not valid") : ""

                    PasswordField {
                        hidden: false
                        text: routeRow.entry.destination
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.routes[routeRow.index].destination = text.trim()
                            form.edited()
                        }
                    }
                }

                FormField {
                    label: form.ip6 ? qsTr("Prefix") : qsTr("Netmask")
                    Layout.preferredWidth: 120
                    Layout.fillWidth: false

                    PasswordField {
                        hidden: false
                        text: routeRow.entry.prefix >= 0 ? String(routeRow.entry.prefix) : ""
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.routes[routeRow.index].prefix = Texts.prefixOf(text, form.ip6)
                            form.edited()
                        }
                    }
                }

                FormField {
                    label: qsTr("Gateway")

                    PasswordField {
                        hidden: false
                        text: routeRow.entry.gateway
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.routes[routeRow.index].gateway = text.trim()
                            form.edited()
                        }
                    }
                }

                FormField {
                    label: qsTr("Metric")
                    Layout.preferredWidth: 90
                    Layout.fillWidth: false

                    PasswordField {
                        hidden: false
                        text: routeRow.entry.metric >= 0 ? String(routeRow.entry.metric) : ""
                        placeholderText: qsTr("Auto")
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 0; top: 2147483647 }
                        Layout.fillWidth: true
                        onTextEdited: {
                            form.ip.routes[routeRow.index].metric = text.length > 0 ? parseInt(text) : -1
                            form.edited()
                        }
                    }
                }

                IconButton {
                    iconName: "user-trash-symbolic"
                    tip: qsTr("Remove this route")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        form.ip.routes.splice(routeRow.index, 1)
                        form.restructured()
                    }
                }
            }
        }

        StandardButton {
            text: qsTr("Add route")
            iconName: "list-add-symbolic"
            onClicked: {
                form.ip.routes.push({ destination: "", prefix: form.ip6 ? 64 : 24, gateway: "", metric: -1 })
                form.restructured()
            }
        }
    }

    SettingsGroup {
        visible: form.configured

        SettingsCard {
            title: qsTr("Use this connection only for resources on its network")
            description: qsTr("The internet is reached through another connection")

            LSwitch {
                checked: form.revision >= 0 && form.ip ? form.ip.neverDefault : false
                Accessible.name: qsTr("Use this connection only for resources on its network")
                onToggled: form.set("neverDefault", checked)
            }
        }
    }
}
