import QtQuick

import MaiaFrontend

// One module of the Control Center: a rounded platter of the translucent Control Center material.
// The modules lie on the dimmed desktop one by one, without a panel around them, as in iPadOS.
Rectangle {
    id: platter

    // 0..1 while the Control Center opens and closes (ControlCenter.qml): the modules grow out of
    // the corner one after the other
    property real appear: 1
    // Lit while the pointer is on a platter that acts as a whole
    property bool highlighted: false

    radius: 24
    color: highlighted ? Theme.moduleHover : Theme.module
    border.width: 1
    border.color: Theme.hairline

    opacity: Math.max(0, Math.min(1, appear))
    scale: 0.82 + 0.18 * appear

    Behavior on color {
        ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
}
