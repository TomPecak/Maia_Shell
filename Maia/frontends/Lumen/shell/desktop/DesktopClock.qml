import QtQuick
import QtQuick.Effects

import LumenFrontend

// Large clock with the date placed on the desktop
Column {
    id: clock

    spacing: 0

    layer.enabled: true
    layer.effect: MultiEffect {
        // Soft shadow keeps the text readable on any part of the wallpaper
        shadowEnabled: true
        shadowColor: Theme.dark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(1, 1, 1, 0.6)
        shadowBlur: 0.6
        shadowVerticalOffset: 1
    }

    LText {
        anchors.right: parent.right
        text: Shell.now.toLocaleTimeString(Qt.locale(), "HH:mm")
        font.pixelSize: 96
        font.weight: Font.Light
    }

    LText {
        anchors.right: parent.right
        rightPadding: 4
        text: {
            const date = Shell.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
            return date.charAt(0).toUpperCase() + date.slice(1)
        }
        font.pixelSize: Theme.fontSubtitle
        color: Theme.textSecondary
    }
}
