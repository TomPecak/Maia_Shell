import QtQuick
import QtQuick.Controls.impl

import ".."

// Icon of the Lumen UI.
//
// tinted: true (default) - symbolic UI icon shipped with the frontend (assets/icons/<name>.svg),
//         tinted with the text color of the theme, so it is readable on light and dark surfaces
//         and does not depend on the icon theme of the user (e.g. Oxygen has no symbolic icons)
// tinted: false - colorful application icon taken from the icon theme of the user
IconImage {
    id: icon

    property string iconName
    property int size: 16
    property bool tinted: true
    property color tint: Theme.textPrimary

    width: size
    height: size
    sourceSize: Qt.size(size, size)

    name: tinted ? "" : iconName
    source: tinted && iconName.length > 0 ? Qt.resolvedUrl("../assets/icons/" + iconName + ".svg") : ""
    color: tinted ? tint : "transparent"
}
