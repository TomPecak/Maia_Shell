import QtQuick
import QtQuick.Controls.Basic

// Button placed in the dock, look taken from the Quickshell dock (Launcher.qml).
// Size and position are set by the dock layout.
//
// QtQuick.Controls.Basic is used explicitly, so the look does not depend on
// the Qt Quick Controls style of the platform (e.g. org.kde.breeze).
Button {
    id: control

    // Icon from the icon theme, e.g. "org.gnome.Calculator"
    property alias iconName: control.icon.name
    // Icon from a file, e.g. Qt.resolvedUrl("../assets/pngegg.png")
    property alias iconSource: control.icon.source
    // Text displayed under the icon, empty = icon only
    property alias appText: control.text

    hoverEnabled: true

    icon.width: width - 16
    icon.height: height - 16
    // Keep the original icon colors (the Basic style would colorize it)
    icon.color: "transparent"

    display: control.text === "" ? AbstractButton.IconOnly : AbstractButton.TextUnderIcon

    // Scale effect: pressed -> 90%, hovered -> 108%, default -> 100%
    scale: control.pressed ? 0.90 : (control.hovered ? 1.08 : 1.0)
    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    background: Rectangle {
        radius: control.width * 0.2

        // Pressed -> darker gray, hovered -> light gray, default -> white
        color: control.pressed ? "#d0d0d0" : (control.hovered ? "#f0f0f0" : "white")
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
    }
}
