import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Settings
import Maia.Network

// The 802.1X details of an Enterprise network (docs #22): the EAP method and what it needs.
// Fields appear for the chosen method only, in the order an administrator's instructions give
// them (method, then account, then certificates).
//
// eap: the settings' security.eap object, changed in place; the passwords are secrets, kept apart.
ColumnLayout {
    id: form

    property var eap
    property int revision
    // Bumped when the settings are (re)loaded: the text fields take their values again
    property int loaded
    property string password
    property string keyPassword
    // An existing profile: an empty password keeps the saved one
    property bool editing: false

    signal edited()

    readonly property int method: revision >= 0 && eap ? eap.method : Network.EapMethod.Peap
    readonly property bool tls: method === Network.EapMethod.Tls
    readonly property bool needsPassword: !tls
    readonly property bool tunneled: method === Network.EapMethod.Peap || method === Network.EapMethod.Ttls || method === Network.EapMethod.Fast
    readonly property bool valid: revision >= 0 && eap
                                  && eap.identity.length > 0
                                  && (!needsPassword || editing || password.length > 0)
                                  && (!tls || (eap.clientCertificate.length > 0 && eap.privateKey.length > 0))

    function set(key, value) {
        eap[key] = value
        edited()
    }

    spacing: Theme.spacingL
    Layout.fillWidth: true

    FormField {
        label: qsTr("Authentication")

        ComboField {
            Layout.fillWidth: true
            model: [{ text: qsTr("Protected EAP (PEAP)"), value: Network.EapMethod.Peap },
                    { text: qsTr("Tunneled TLS (TTLS)"), value: Network.EapMethod.Ttls },
                    { text: qsTr("TLS (certificate)"), value: Network.EapMethod.Tls },
                    { text: qsTr("PWD"), value: Network.EapMethod.Pwd },
                    { text: qsTr("FAST"), value: Network.EapMethod.Fast },
                    { text: qsTr("LEAP"), value: Network.EapMethod.Leap }]
            currentIndex: form.revision >= 0 ? indexOfValue(form.method) : 0
            onActivated: {
                form.set("method", currentValue)
                // An inner method the new outer one does not offer would be refused
                const inner = form.innerChoices().map(c => c.value)
                if (inner.length > 0 && inner.indexOf(form.eap.innerAuth) < 0)
                    form.set("innerAuth", inner[0])
            }
        }
    }

    FormField {
        label: form.tls ? qsTr("Identity") : qsTr("User name")

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.eap ? form.eap.identity : ""
            Layout.fillWidth: true
            onTextEdited: form.set("identity", text)
        }
    }

    FormField {
        visible: form.needsPassword
        label: qsTr("Password")
        help: form.editing ? qsTr("Leave empty to keep the saved password.") : ""

        PasswordField {
            text: form.password
            Layout.fillWidth: true
            placeholderText: form.editing ? qsTr("Unchanged") : ""
            onTextEdited: {
                form.password = text
                form.edited()
            }
        }
    }

    FormField {
        visible: form.tunneled
        label: qsTr("Anonymous identity")
        help: qsTr("Sent before the secure tunnel is set up. Optional.")

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.eap ? form.eap.anonymousIdentity : ""
            Layout.fillWidth: true
            onTextEdited: form.set("anonymousIdentity", text)
        }
    }

    function innerChoices() {
        switch (form.method) {
        case Network.EapMethod.Peap:
            return [{ text: "MSCHAPv2", value: Network.InnerAuth.Mschapv2 }, { text: "MD5", value: Network.InnerAuth.Md5 },
                    { text: "GTC", value: Network.InnerAuth.Gtc }]
        case Network.EapMethod.Ttls:
            return [{ text: "PAP", value: Network.InnerAuth.Pap }, { text: "MSCHAP", value: Network.InnerAuth.Mschap },
                    { text: "MSCHAPv2", value: Network.InnerAuth.Mschapv2 }, { text: "CHAP", value: Network.InnerAuth.Chap }]
        case Network.EapMethod.Fast:
            return [{ text: "GTC", value: Network.InnerAuth.Gtc }, { text: "MSCHAPv2", value: Network.InnerAuth.Mschapv2 }]
        }
        return []
    }

    RowLayout {
        visible: form.tunneled
        spacing: Theme.spacingL
        Layout.fillWidth: true

        FormField {
            label: qsTr("Inner authentication")

            ComboField {
                Layout.fillWidth: true
                model: form.revision >= 0 ? form.innerChoices() : []
                currentIndex: form.revision >= 0 && form.eap ? Math.max(0, indexOfValue(form.eap.innerAuth)) : 0
                onActivated: form.set("innerAuth", currentValue)
            }
        }

        FormField {
            visible: form.method === Network.EapMethod.Peap
            label: qsTr("PEAP version")

            ComboField {
                Layout.fillWidth: true
                model: [{ text: qsTr("Automatic"), value: -1 }, { text: qsTr("Version 0"), value: 0 }, { text: qsTr("Version 1"), value: 1 }]
                currentIndex: form.revision >= 0 && form.eap ? Math.max(0, indexOfValue(form.eap.peapVersion)) : 0
                onActivated: form.set("peapVersion", currentValue)
            }
        }
    }

    PathField {
        visible: form.method === Network.EapMethod.Fast
        label: qsTr("PAC file")
        nameFilters: [qsTr("PAC files (*.pac)"), qsTr("All files (*)")]
        path: form.loaded >= 0 && form.eap ? form.eap.pacFile : ""
        onEdited: path => form.set("pacFile", path)
    }

    // Certificates: without the CA certificate anyone could pose as the network and get the password
    PathField {
        visible: form.tls || form.method === Network.EapMethod.Peap || form.method === Network.EapMethod.Ttls
        enabled: !(form.revision >= 0 && form.eap && form.eap.noCaCertificate)
        label: qsTr("CA certificate")
        help: qsTr("None: the system's certificates are trusted.")
        path: form.loaded >= 0 && form.eap ? form.eap.caCertificate : ""
        onEdited: path => form.set("caCertificate", path)
    }

    RowLayout {
        visible: form.tls || form.method === Network.EapMethod.Peap || form.method === Network.EapMethod.Ttls
        spacing: Theme.spacingM
        Layout.fillWidth: true

        LSwitch {
            id: noCa
            checked: form.revision >= 0 && form.eap ? form.eap.noCaCertificate : false
            Accessible.name: qsTr("No CA certificate is required")
            onToggled: form.set("noCaCertificate", checked)
        }

        LText {
            text: qsTr("No CA certificate is required")
            Layout.fillWidth: true
        }
    }

    InfoBar {
        visible: noCa.checked && noCa.visible
        severity: "warning"
        message: qsTr("Without a CA certificate this computer cannot tell the real network from one that pretends to be it.")
    }

    FormField {
        visible: form.tls || form.method === Network.EapMethod.Peap || form.method === Network.EapMethod.Ttls
        label: qsTr("Domain")
        help: qsTr("The server's certificate must belong to this domain. Optional.")

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.eap ? form.eap.domain : ""
            placeholderText: "example.com"
            Layout.fillWidth: true
            onTextEdited: form.set("domain", text)
        }
    }

    PathField {
        visible: form.tls
        label: qsTr("User certificate")
        path: form.loaded >= 0 && form.eap ? form.eap.clientCertificate : ""
        onEdited: path => form.set("clientCertificate", path)
    }

    PathField {
        visible: form.tls
        label: qsTr("Private key")
        path: form.loaded >= 0 && form.eap ? form.eap.privateKey : ""
        onEdited: path => form.set("privateKey", path)
    }

    FormField {
        visible: form.tls
        label: qsTr("Private key password")

        PasswordField {
            text: form.keyPassword
            Layout.fillWidth: true
            placeholderText: form.editing ? qsTr("Unchanged") : ""
            onTextEdited: {
                form.keyPassword = text
                form.edited()
            }
        }
    }
}
