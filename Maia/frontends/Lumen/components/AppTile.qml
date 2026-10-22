import QtQuick

import LumenFrontend

// Application in the start menu grid: icon with the name under it
SubtleButton {
    id: control

    // Icon url, e.g. "image://backend_app_icon/firefox" or Theme.iconUrl("kate")
    property url iconSource

    implicitWidth: 96
    implicitHeight: 84
    radius: Theme.radiusSmall
    padding: Theme.spacingXS

    contentItem: Item {
        Image {
            id: icon

            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.spacingS
            width: 32
            height: 32
            sourceSize: Qt.size(32, 32)
            source: control.iconSource
            asynchronous: true

            scale: control.pressed ? 0.85 : 1.0
            Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
        }

        LText {
            anchors.top: icon.bottom
            anchors.topMargin: Theme.spacingS
            width: parent.width
            text: control.text
            font.pixelSize: Theme.fontCaption
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
