import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// A module of one cell: a single toggle or button, its glyph in the middle. When on, the whole
// platter takes the color of its function, as the small modules of iPadOS do.
ModulePlatter {
    id: tile

    property string title
    property url icon
    property color onColor: Theme.blue
    property bool checked: false
    // A plain button (Settings): never "on"
    property bool checkable: true

    signal clicked()

    highlighted: area.containsMouse && !tile.checked
    color: tile.checked ? tile.onColor : highlighted ? Theme.moduleHover : Theme.module

    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.name: title
    Accessible.checkable: checkable
    Accessible.checked: checked
    Accessible.onPressAction: tile.clicked()

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 26
        height: 26
        scale: area.pressed ? 0.88 : 1
        source: tile.icon
        isMask: true
        color: tile.checked ? "white" : Theme.label

        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        onClicked: tile.clicked()
    }
}
