import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// The round toggle of the Control Center: a gray circle when off, the color of its function when
// on (blue for connections, orange for airplane mode and night light), with a white glyph. The
// circle is the target of the toggle; the text next to it may open more (ConnectivityModule).
Item {
    id: toggle

    property bool checked: false
    property color onColor: Theme.blue
    // A glyph shipped with the frontend, or glyph for a drawn one
    property url icon
    property Component glyph: null
    property real size: 44
    // Without a reaction of its own (the whole tile acts, WideTile.qml)
    property bool interactive: true
    // Shown under the pointer of the tile that contains it
    property bool hovered: false

    signal clicked()

    width: size
    height: size

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: toggle.clicked()
    Accessible.onToggleAction: toggle.clicked()

    Rectangle {
        id: circle

        anchors.fill: parent
        radius: width / 2
        color: toggle.checked ? toggle.onColor : Theme.toggleOff
        scale: area.pressed ? 0.9 : area.containsMouse || toggle.hovered ? 1.05 : 1

        Behavior on color {
            ColorAnimation { duration: 180; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            ScaleAnimator { duration: 160; easing.type: Easing.OutCubic }
        }

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(toggle.size * 0.44)
            height: width
            visible: !toggle.glyph
            source: toggle.icon
            isMask: true
            color: toggle.checked ? "white" : Theme.label
        }

        Loader {
            anchors.centerIn: parent
            width: Math.round(toggle.size * 0.46)
            height: width
            sourceComponent: toggle.glyph
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: toggle.interactive
        hoverEnabled: true
        onClicked: toggle.clicked()
    }
}
