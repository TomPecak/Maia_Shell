import QtQuick
import org.kde.kirigami as Kirigami

import LumenFrontend

// One icon of the system tray in the taskbar (or in its overflow): the application's icon (its
// attention icon while it needs attention), a dot of the accent then, and its tool tip.
//
//   click                  activated(), or menuRequested() for an item that is only a menu
//   right click            menuRequested() (contextMenuRequested() for an item without a menu)
//   middle click           secondaryActivated()
//   wheel                  scrolled(delta, horizontal), 120 a notch
SubtleButton {
    id: button

    property string source
    // The image is one grey on transparency (a template): drawn in the text's colour
    property bool isMask: false
    property string overlaySource
    property bool needsAttention: false
    property bool hasMenu: false
    property bool itemIsMenu: false
    property string toolTip
    property int iconSize: 18

    signal activated()
    signal secondaryActivated()
    signal menuRequested()
    signal contextMenuRequested()
    signal scrolled(int delta, bool horizontal)

    // Monochrome icons of the theme (Breeze) take Lumen's text colour of light or dark mode
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.textColor: Theme.textPrimary
    Kirigami.Theme.backgroundColor: Theme.taskbar

    implicitWidth: 32
    implicitHeight: 40
    padding: 0
    Accessible.description: needsAttention ? qsTr("needs attention") : ""

    onClicked: itemIsMenu && hasMenu ? menuRequested() : activated()

    contentItem: Item {
        Kirigami.Icon {
            id: image

            objectName: "trayIconImage"
            anchors.centerIn: parent
            width: button.iconSize
            height: button.iconSize
            source: button.source
            fallback: "application-x-executable"
            isMask: button.isMask
            color: Theme.textPrimary
            scale: button.pressed ? 0.82 : 1.0

            Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }
        }

        Kirigami.Icon {
            anchors.right: image.right
            anchors.bottom: image.bottom
            anchors.margins: -2
            width: Math.round(button.iconSize / 2)
            height: width
            visible: button.overlaySource !== ""
            source: button.overlaySource
        }

        Rectangle {
            objectName: "attentionDot"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            width: 6
            height: 3
            radius: 1.5
            color: Theme.accent
            opacity: button.needsAttention ? 1 : 0

            Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
        }
    }

    // The buttons other than the left one, and the wheel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.MiddleButton

        // Small wheels and touchpads send parts of a notch
        property int pendingDelta: 0

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                button.secondaryActivated()
            else
                button.hasMenu ? button.menuRequested() : button.contextMenuRequested()
        }
        onWheel: wheel => {
            const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
            pendingDelta += horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
            if (Math.abs(pendingDelta) >= 120) {
                button.scrolled(pendingDelta, horizontal)
                pendingDelta = 0
            }
        }
    }

    LToolTip {
        text: button.toolTip
    }
}
