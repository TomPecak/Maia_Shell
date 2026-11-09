import QtQuick

import MaiaFrontend
import ".."

// The power button at the end of the strip the dock reserves. It sits in the reserved strip, so
// it never covers a window (the corners outside the strip hold the buttons of maximized windows);
// it is last, in the corner, where system controls are on every desktop. The Control Center is at
// the other end of the strip (shell/controlcenter/). Moves with the dock (StripItem.qml).
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
