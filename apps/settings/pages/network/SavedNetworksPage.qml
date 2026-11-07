import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.SettingsKit
import Maia.Network

import "Texts.js" as Texts

// Settings › Wi-Fi › Saved networks (docs #10, #11): the last used first; share, details, forget.
// Forget hides the row at once and deletes the profile only when the "Undo" message is gone,
// as GNOME does: a slip is undone with one click, and nothing asks "Are you sure?".
SettingsPage {
    id: page

    title: qsTr("Saved networks")

    // Profiles forgotten but not deleted yet (their undo message is still shown)
    property var pending: []

    function forget(uuid) {
        pending = pending.concat([uuid])
        const forgotten = pending.slice()
        SettingsApp.toast(forgotten.length === 1 ? qsTr("Network forgotten") : qsTr("%1 networks forgotten").arg(forgotten.length),
                          qsTr("Undo"),
                          () => { page.pending = [] },
                          () => {
                              for (const id of forgotten)
                                  saved.forget(id)
                              page.pending = page.pending.filter(id => forgotten.indexOf(id) < 0)
                          })
    }

    // Testing: forget the first network once the list is there
    property bool testForget: false
    Timer {
        running: page.testForget && saved.count > 0
        interval: 300
        onTriggered: page.forget(saved.data(saved.index(0, 0), SavedNetworksModel.UuidRole))
    }

    SavedNetworksModel { id: saved }
    ShareDialog { id: shareDialog }

    EmptyState {
        visible: saved.count === 0 || saved.count === page.pending.length
        iconName: "network-wireless-signal-none-symbolic"
        title: qsTr("No saved networks")
        description: qsTr("Networks you connect to are saved here, so this computer connects to them again by itself.")
    }

    SettingsGroup {
        visible: saved.count > page.pending.length

        Repeater {
            model: saved

            SettingsCard {
                id: row

                required property string uuid
                required property string name
                required property int security
                required property bool secure
                required property bool hidden
                required property var lastUsed
                required property bool active
                required property string activeDeviceId
                required property bool inRange
                required property int signalLevel
                required property bool qrSupported

                visible: page.pending.indexOf(uuid) < 0
                iconName: inRange ? Texts.signalIcon(signalLevel) : "network-wireless-disconnected-symbolic"
                title: name
                description: active ? qsTr("Connected")
                           : [inRange ? qsTr("In reach") : qsTr("Not in reach"),
                              qsTr("Last used: %1").arg(Texts.lastUsed(lastUsed)),
                              hidden ? qsTr("Hidden") : ""].filter(s => s.length > 0).join(" · ")
                descriptionColor: active ? Theme.accent : Theme.textSecondary
                clickable: true
                chevron: false
                onClicked: SettingsApp.push(Qt.resolvedUrl("NetworkDetailsPage.qml"), { uuid: uuid, deviceId: activeDeviceId, networkId: "" })

                IconButton {
                    visible: row.qrSupported
                    iconName: "view-barcode-qr-symbolic"
                    tip: qsTr("Share this network (QR code)")
                    onClicked: shareDialog.openFor(row.uuid)
                }

                IconButton {
                    iconName: "configure-symbolic"
                    tip: qsTr("Network details")
                    onClicked: row.clicked()
                }

                IconButton {
                    iconName: "user-trash-symbolic"
                    tip: qsTr("Forget this network")
                    onClicked: page.forget(row.uuid)
                }
            }
        }
    }

    // Leaving the page while the message waits: the forgetting happens now, while the page exists
    Component.onDestruction: {
        if (pending.length > 0)
            SettingsApp.dismissToast()
    }
}
