import QtQuick
import QtQuick.Controls

MenuItem {
    id: root

    implicitHeight: 17
    implicitWidth: 121

    property alias fontWeight: contentText.font.weight
    property bool active: true

    contentItem: Text {
        id: contentText
        leftPadding: 11
        rightPadding: root.arrow.width

        text: root.text

        font.family: "Tahoma"
        font.weight: Font.Normal
        font.pointSize: 8.0
        font.kerning: true
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
        antialiasing: false

        color: root.active ? (root.highlighted ? "#ffffff" : "#000000") : "#aca899"
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    arrow: Image{
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 7
        visible: root.subMenu
        smooth: false
        sourceSize.width: 4
        sourceSize.height: 7
        mipmap: true
        source: "../assets/images/arrow_pixel_art.png"
    }

    // arrow: Canvas {
    //     x: parent.width - width
    //     implicitWidth: 40
    //     implicitHeight: 40
    //     visible: root.subMenu
    //     onPaint: {
    //         var ctx = getContext("2d")
    //         //ctx.fillStyle = menuItem.highlighted ? "#ffffff" : "#21be2b"
    //         ctx.fillStyle = "#21be2b"
    //         ctx.moveTo(15, 15)
    //         ctx.lineTo(width - 15, height / 2)
    //         ctx.lineTo(15, height - 15)
    //         ctx.closePath()
    //         ctx.fill()
    //     }
    // }

    background: Rectangle {
        anchors.fill: parent
        implicitWidth: 200
        implicitHeight: 40
        color: root.highlighted ? "#316ac5" : "#ffffff"
    }
}
