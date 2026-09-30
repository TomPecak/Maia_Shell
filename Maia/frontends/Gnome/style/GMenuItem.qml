import QtQuick
import QtQuick.Controls
import "./"
import "../"

MenuItem {

    id: root

    leftPadding: 0
    rightPadding: 0

    // implicitHeight: 32
    // implicitWidth: 213

    property bool active: true

    contentItem: Text{

        leftPadding: 32
        rightPadding: 32
        text: root.text
        font.family: "Ubuntu Sans"
        font.pointSize: 11
        verticalAlignment: Text.AlignVCenter
        color: root.active ? UIStyle.colorControlBoardIcon : UIStyle.disabledTextColor
    }

    // arrow: Canvas {
    //     x: parent.width - width
    //     implicitWidth: implicitHeight
    //     implicitHeight: root.height
    //     visible: root.subMenu
    //     onPaint: {
    //         var ctx = getContext("2d")
    //         //ctx.fillStyle = menuItem.highlighted ? "#ffffff" : "#21be2b"
    //         ctx.fillStyle = "#21be2b"
    //         ctx.moveTo(0, 0)
    //         ctx.lineTo(width - 15, height / 2)
    //         ctx.lineTo(15, height - 15)
    //         ctx.closePath()
    //         ctx.fill()

    //         // ctx.fillStyle = "#21be2b"
    //         // ctx.moveTo(0, 0)
    //         // ctx.lineTo(10, 0)
    //         // ctx.lineTo(10, 10)
    //         // ctx.lineTo(0, 10)
    //         // ctx.closePath()
    //         // ctx.fill()
    //     }

    // }

    arrow: Item{
        x: parent.width - width
        implicitWidth: implicitHeight
        implicitHeight: root.height
        visible: root.subMenu

        Button {
            id: iconBtn
            height: parent.height * 0.8
            width: parent.width * 0.8
            anchors.centerIn: parent

            icon.source: "../icons/right.svg"
            //icon.source: "../icons/right-large.svg"
            icon.color: UIStyle.colorButtonSystemSettingsIcon
            icon.width: iconBtn.width
            icon.height: iconBtn.height

            display: AbstractButton.IconOnly

            background: null
        }
    }

    background: Rectangle{
        anchors.fill: parent
        implicitHeight: 32
        implicitWidth: 213
        color: root.active ? (root.highlighted ? ("#dedede") : (root.hovered ? "#dedede" : "#FFFFFF")) : "#FFFFFF"
        radius: 4
        Behavior on color {

            ColorAnimation {
                duration: 60
            }
        }
    }
}
