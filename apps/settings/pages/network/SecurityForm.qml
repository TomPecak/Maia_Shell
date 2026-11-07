import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// The security of a network: its type and what that type needs (a password, a WEP key, a LEAP
// account or the 802.1X details). Used by the hidden network dialog and the details page.
//
// security: the settings' security object, changed in place. secrets() gives what was typed.
ColumnLayout {
    id: form

    property var security
    property int revision
    // Bumped when the settings are (re)loaded: the text fields take their values again
    property int loaded
    // An existing profile: empty secrets keep the saved ones
    property bool editing: false

    property string password
    property string wepKey
    property string leapPassword

    signal edited()

    readonly property int type: revision >= 0 && security ? security.security : Network.Security.None
    readonly property bool valid: {
        if (revision < 0 || !security)
            return false
        if (Texts.isPersonal(type))
            return (editing && password.length === 0) || Texts.validWpaPassword(password)
        if (type === Network.Security.Wep)
            return (editing && wepKey.length === 0) || Texts.validWepKey(wepKey, security.wepPassphrase)
        if (type === Network.Security.Leap)
            return security.leapUsername.length > 0 && (editing || leapPassword.length > 0)
        if (Texts.isEnterprise(type))
            return eap.valid
        return true
    }

    // The secrets the user typed, for connectWithSettings / updateSettings
    function secrets() {
        const list = []
        if (Texts.isPersonal(type) && password.length > 0)
            list.push({ key: Network.SecretKey.WifiPassword, value: password })
        if (type === Network.Security.Wep && wepKey.length > 0)
            list.push({ key: Network.SecretKey.WepKey, value: wepKey })
        if (type === Network.Security.Leap && leapPassword.length > 0)
            list.push({ key: Network.SecretKey.LeapPassword, value: leapPassword })
        if (Texts.isEnterprise(type)) {
            if (eap.password.length > 0)
                list.push({ key: Network.SecretKey.EapPassword, value: eap.password })
            if (eap.keyPassword.length > 0)
                list.push({ key: Network.SecretKey.EapPrivateKeyPassword, value: eap.keyPassword })
        }
        return list
    }

    // Fills the fields with saved secrets (from NetworkControl.secrets)
    function showSecrets(list) {
        for (const s of list) {
            if (s.key === Network.SecretKey.WifiPassword) password = s.value
            else if (s.key === Network.SecretKey.WepKey) wepKey = s.value
            else if (s.key === Network.SecretKey.LeapPassword) leapPassword = s.value
            else if (s.key === Network.SecretKey.EapPassword) eap.password = s.value
            else if (s.key === Network.SecretKey.EapPrivateKeyPassword) eap.keyPassword = s.value
        }
    }

    // A "show the saved password" link for existing profiles (asks polkit when needed)
    property bool canLoadSecrets: false
    signal loadSecretsRequested()

    spacing: Theme.spacingL
    Layout.fillWidth: true

    FormField {
        label: qsTr("Security")

        ComboField {
            Layout.fillWidth: true
            model: Texts.securityChoices(form.type)
            currentIndex: form.revision >= 0 ? Math.max(0, indexOfValue(form.type)) : 0
            onActivated: {
                form.security.security = currentValue
                form.edited()
            }
        }
    }

    InfoBar {
        visible: form.type === Network.Security.Wep || form.type === Network.Security.Leap
        severity: "warning"
        message: qsTr("%1 is not secure any more: others nearby can read what is sent. Change the router to WPA2 or WPA3 if you can.")
                 .arg(Texts.security(form.type))
    }

    InfoBar {
        visible: form.type === Network.Security.None
        severity: "info"
        message: qsTr("On an open network others nearby can see what is sent.")
    }

    FormField {
        visible: Texts.isPersonal(form.type)
        label: qsTr("Password")
        error: form.password.length > 0 && !Texts.validWpaPassword(form.password) ? qsTr("A password has 8 to 63 characters.") : ""
        help: form.editing ? qsTr("Leave empty to keep the saved password.") : ""

        PasswordField {
            text: form.password
            placeholderText: form.editing ? qsTr("Unchanged") : ""
            Layout.fillWidth: true
            Accessible.name: qsTr("Password")
            onTextEdited: {
                form.password = text
                form.edited()
            }
        }
    }

    // WEP: the key and how it is given
    RowLayout {
        visible: form.type === Network.Security.Wep
        spacing: Theme.spacingL
        Layout.fillWidth: true

        FormField {
            label: qsTr("Key type")

            ComboField {
                Layout.fillWidth: true
                model: [{ text: qsTr("Key (hex or ASCII)"), value: false }, { text: qsTr("Passphrase"), value: true }]
                currentIndex: form.revision >= 0 && form.security && form.security.wepPassphrase ? 1 : 0
                onActivated: {
                    form.security.wepPassphrase = currentValue
                    form.edited()
                }
            }
        }

        FormField {
            label: qsTr("Key index")

            ComboField {
                Layout.fillWidth: true
                model: [0, 1, 2, 3].map(i => ({ text: String(i + 1), value: i }))
                currentIndex: form.revision >= 0 && form.security ? form.security.wepKeyIndex : 0
                onActivated: {
                    form.security.wepKeyIndex = currentValue
                    form.edited()
                }
            }
        }
    }

    FormField {
        visible: form.type === Network.Security.Wep
        label: qsTr("Key")
        error: form.wepKey.length > 0 && !Texts.validWepKey(form.wepKey, form.security && form.security.wepPassphrase)
               ? qsTr("A WEP key has 5 or 13 characters, or 10 or 26 hexadecimal digits.") : ""

        PasswordField {
            text: form.wepKey
            placeholderText: form.editing ? qsTr("Unchanged") : ""
            Layout.fillWidth: true
            onTextEdited: {
                form.wepKey = text
                form.edited()
            }
        }
    }

    FormField {
        visible: form.type === Network.Security.Leap
        label: qsTr("User name")

        PasswordField {
            hidden: false
            text: form.loaded >= 0 && form.security ? form.security.leapUsername : ""
            Layout.fillWidth: true
            onTextEdited: {
                form.security.leapUsername = text
                form.edited()
            }
        }
    }

    FormField {
        visible: form.type === Network.Security.Leap
        label: qsTr("Password")

        PasswordField {
            text: form.leapPassword
            placeholderText: form.editing ? qsTr("Unchanged") : ""
            Layout.fillWidth: true
            onTextEdited: {
                form.leapPassword = text
                form.edited()
            }
        }
    }

    EapForm {
        id: eap

        visible: Texts.isEnterprise(form.type)
        eap: form.security ? form.security.eap : null
        revision: form.revision
        loaded: form.loaded
        editing: form.editing
        onEdited: form.edited()
    }

    LText {
        visible: form.canLoadSecrets && form.type !== Network.Security.None && form.type !== Network.Security.EnhancedOpen
        text: qsTr("Show the saved password")
        color: showLink.containsMouse ? Theme.accentHover : Theme.accent

        MouseArea {
            id: showLink
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: form.loadSecretsRequested()
        }
    }
}
