import QtQuick
import QtQuick.Controls.impl
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Row of MenuPanel in the style of iPadOS: the title on the left, the symbol on the right.
// A row opening a submenu shows a chevron instead of the symbol; the header of a submenu
// (header: true) has a bold title and a chevron pointing down.
T.AbstractButton {
    id: item

    property string iconName
    // An application's icon instead (a theme name or an image URL: a tray menu's entries)
    property string iconSource
    // That icon is one grey on transparency: drawn in the label's colour
    property bool iconIsMask: false
    property bool hasSubmenu: false
    property bool header: false
    // Reserves a column on the left for the check mark (choice lists)
    property bool checkColumn: false

    // The label colors of iPadOS: primary label (black) and tertiary label (60, 60, 67 at 30 %)
    readonly property color labelColor: "black"
    readonly property color disabledColor: Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.3)

    width: parent ? parent.width : implicitWidth
    implicitHeight: 42
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    leftInset: 6
    rightInset: 6
    leftPadding: checkColumn ? 12 : 18
    rightPadding: 18

    Accessible.role: hasSubmenu ? Accessible.ButtonMenu : Accessible.MenuItem
    Accessible.name: text

    // Highlight of the hovered / pressed row: one dark layer whose opacity changes, so the change
    // can be an Animator (render thread); there is no animator for colors
    background: Rectangle {
        radius: 9
        color: "black"
        opacity: !item.enabled ? 0
               : item.pressed ? 0.14
               : item.hovered ? 0.07
               : 0

        Behavior on opacity { OpacityAnimator { duration: 90 } }
    }

    contentItem: Item {
        IconImage {
            id: check

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            sourceSize: Qt.size(16, 16)
            visible: item.checkColumn && item.checked
            source: Qt.resolvedUrl("../../assets/icons/checkmark-symbolic.svg")
            color: item.labelColor
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: item.checkColumn ? 16 + 10 : 0
            anchors.right: appIcon.visible ? appIcon.left : symbol.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: item.text
            color: item.enabled ? item.labelColor : item.disabledColor
            font.pixelSize: 16
            font.weight: item.header ? Font.DemiBold : Font.Normal
            font.letterSpacing: -0.2
            elide: Text.ElideRight
        }

        IconImage {
            id: symbol

            readonly property string symbolName: item.header ? "go-down-symbolic"
                                               : item.hasSubmenu ? "go-next-symbolic"
                                               : item.iconName

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: item.hasSubmenu || item.header ? 14 : 18
            height: width
            sourceSize: Qt.size(width, height)
            source: symbolName.length > 0 ? Qt.resolvedUrl("../../assets/icons/" + symbolName + ".svg") : ""
            color: item.enabled ? item.labelColor : item.disabledColor
            visible: !appIcon.visible
        }

        Kirigami.Icon {
            id: appIcon

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            visible: item.iconSource !== "" && !item.hasSubmenu && !item.header
            source: item.iconSource
            isMask: item.iconIsMask
            color: item.labelColor
            opacity: item.enabled ? 1 : 0.4
        }
    }
}
