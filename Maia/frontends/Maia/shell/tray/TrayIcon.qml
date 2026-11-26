import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// One icon of the system tray: the application's icon (its attention icon while it needs
// attention), the small sign it may draw over it, and the input of a tray icon:
//
//   tap or click           activated(), or menuRequested() for an item that is only a menu
//   long press, right click menuRequested() (contextMenuRequested() for an item without a menu)
//   middle click           secondaryActivated()
//   wheel                  scrolled(delta, horizontal), 120 a notch
//
// An item that needs attention lies on a soft tint of the accent with a dot in its corner; the
// tint comes and goes with an Animator, nothing else moves.
Item {
    id: icon

    property string source
    property string overlaySource
    property bool needsAttention: false
    property bool hasMenu: false
    property bool itemIsMenu: false
    // Its menu is open: it looks pressed meanwhile
    property bool checked: false
    property real iconSize: 22
    property string name

    readonly property bool pressed: mouse.pressed

    signal activated()
    signal secondaryActivated()
    signal menuRequested()
    signal contextMenuRequested()
    signal scrolled(int delta, bool horizontal)

    implicitWidth: 32
    implicitHeight: 32

    // Monochrome icons of the theme (Breeze) take the label's colour of Maia's light or dark mode,
    // as a panel of Plasma recolours them
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.textColor: Theme.label
    Kirigami.Theme.backgroundColor: Theme.dock

    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.onPressAction: icon.itemIsMenu && icon.hasMenu ? icon.menuRequested() : icon.activated()

    // Attention: the tint behind the icon
    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Theme.accent
        opacity: icon.needsAttention ? 0.18 : 0

        Behavior on opacity {
            OpacityAnimator { duration: 220; easing.type: Easing.OutCubic }
        }
    }

    // Under the pointer, pressed, or with its menu open
    Rectangle {
        anchors.fill: parent
        radius: 9
        color: icon.pressed || icon.checked ? Theme.pressed : Theme.hover
        opacity: icon.pressed || icon.checked || mouse.containsMouse ? 1 : 0

        Behavior on opacity {
            OpacityAnimator { duration: 120; easing.type: Easing.OutQuad }
        }
    }

    Kirigami.Icon {
        id: image

        anchors.centerIn: parent
        width: icon.iconSize
        height: icon.iconSize
        source: icon.source
        fallback: "application-x-executable"
        scale: icon.pressed ? 0.9 : 1

        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    Kirigami.Icon {
        anchors.right: image.right
        anchors.bottom: image.bottom
        anchors.margins: -2
        width: Math.round(icon.iconSize * 0.5)
        height: width
        visible: icon.overlaySource !== ""
        source: icon.overlaySource
    }

    // Attention: the dot
    Rectangle {
        objectName: "attentionDot"
        x: parent.width - width - 2
        y: 2
        width: 7
        height: 7
        radius: 3.5
        color: Theme.red
        border.width: 1
        border.color: Theme.card
        opacity: icon.needsAttention ? 1 : 0

        Behavior on opacity {
            OpacityAnimator { duration: 220; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        pressAndHoldInterval: 450

        property bool held: false
        // Small wheels and touchpads send parts of a notch
        property int pendingDelta: 0

        onPressed: held = false
        onPressAndHold: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return
            held = true
            icon.hasMenu ? icon.menuRequested() : icon.contextMenuRequested()
        }
        onClicked: mouse => {
            if (held)
                return
            if (mouse.button === Qt.MiddleButton)
                icon.secondaryActivated()
            else if (mouse.button === Qt.RightButton)
                icon.hasMenu ? icon.menuRequested() : icon.contextMenuRequested()
            else if (icon.itemIsMenu && icon.hasMenu)
                icon.menuRequested()
            else
                icon.activated()
        }
        onWheel: wheel => {
            const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
            pendingDelta += horizontal ? wheel.angleDelta.x : wheel.angleDelta.y
            if (Math.abs(pendingDelta) >= 120) {
                icon.scrolled(pendingDelta, horizontal)
                pendingDelta = 0
            }
        }
    }
}
