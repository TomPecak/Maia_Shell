import QtQuick

import MaiaFrontend

// A module of two cells with one function: a round toggle, a name and a state (Dark Mode), or an
// indicator without action (the battery). The whole tile is the target, larger than its circle
// (Fitts's law).
ModulePlatter {
    id: tile

    property string title
    property string subtitle
    property url icon
    property Component glyph: null
    property color onColor: Theme.blue
    property bool checked: false
    // Shows a state only (the battery): no hover, no click
    property bool interactive: true

    signal clicked()

    highlighted: interactive && area.containsMouse

    Accessible.role: interactive ? Accessible.CheckBox : Accessible.StaticText
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.checkable: interactive
    Accessible.checked: checked
    Accessible.onPressAction: if (interactive) tile.clicked()

    RoundToggle {
        id: circle

        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        size: 40
        icon: tile.icon
        glyph: tile.glyph
        onColor: tile.onColor
        checked: tile.checked
        interactive: false
        hovered: tile.highlighted
    }

    Column {
        anchors.left: circle.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: tile.title
            color: Theme.label
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tile.subtitle
            color: Theme.secondaryLabel
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: tile.interactive
        hoverEnabled: true
        onClicked: tile.clicked()
    }
}
