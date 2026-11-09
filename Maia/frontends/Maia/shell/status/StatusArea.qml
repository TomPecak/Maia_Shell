import QtQuick

import MaiaFrontend
import ".."

// The power button at one end of the strip the dock reserves: the left end of a horizontal strip,
// the bottom end of a vertical one. It sits in the reserved strip, so it never covers a window
// (the corners outside the strip hold the buttons of maximized windows). The Control Center is at
// the other end (shell/controlcenter/): top right, where it is on iPadOS. Moves with the dock
// (StripItem.qml).
StripItem {
    id: area

    // The session screen is open
    property bool sessionOpen: false

    // The power button was clicked
    signal powerClicked()

    width: power.width
    height: power.height

    PowerButton {
        id: power

        checked: area.sessionOpen
        onClicked: area.powerClicked()
    }
}
