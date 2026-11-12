import QtQuick

import LumenFrontend
import Maia.SettingsKit

import "Texts.js" as Texts

// One power mode (GNOME: a row of the "Power Mode" group). The whole card chooses it; the round
// mark at the right shows the chosen one.
SettingsCard {
    id: card

    // Power.Profile
    property int profile
    property bool checked: false

    iconName: Texts.profileIcon(profile)
    title: Texts.profileName(profile)
    description: Texts.profileDescription(profile)
    clickable: true
    chevron: false

    Accessible.role: Accessible.RadioButton
    Accessible.name: title
    Accessible.checked: checked

    Rectangle {
        width: 20
        height: 20
        radius: 10
        color: card.checked ? Theme.accent : "transparent"
        border.width: card.checked ? 0 : 1
        border.color: Theme.textSecondary

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            anchors.centerIn: parent
            width: card.checked ? 8 : 0
            height: width
            radius: width / 2
            color: Theme.onAccent

            Behavior on width { NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
        }
    }
}
