import QtQuick
import QtQuick.Templates as T

import ".."

// Transparent button which shows a subtle fill on hover and press (Fluent "subtle"
// button). It is the base of the taskbar, tray and list buttons; the content is set
// by the user of the component.
T.AbstractButton {
    id: control

    property int radius: Theme.radiusSmall
    // Keeps the hover fill, e.g. while the flyout opened by the button is visible
    property bool highlighted: false

    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: Theme.spacingS

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    Accessible.role: Accessible.Button
    Accessible.name: text

    background: Rectangle {
        radius: control.radius
        color: control.pressed ? Theme.subtlePressed
             : (control.hovered || control.highlighted) ? Theme.subtleHover
             : "transparent"
        border.width: control.visualFocus ? 2 : 0
        border.color: Theme.textPrimary

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }
}
