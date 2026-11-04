import QtQuick

import LumenFrontend

// A square button with an icon and a tooltip (the tooltip names what the icon alone cannot)
SubtleButton {
    id: button

    property string iconName
    property string tip
    property color tint: Theme.textPrimary

    implicitWidth: 32
    implicitHeight: 32
    Accessible.name: tip

    contentItem: Item {
        LIcon {
            anchors.centerIn: parent
            iconName: button.iconName
            size: 16
            tint: button.tint
        }
    }

    ToolTipArea { text: button.tip }
}
