import QtQuick
import QtQuick.Controls

import "../style"

TextField {
    id :root

    leftPadding: height
    color: "#e8e8e8"
    placeholderTextColor: "#e8e8e8"
    font.pointSize: 10

    background: Rectangle{
        anchors.fill: parent
        color: root.activeFocus ? "#454545" : (root.hovered ? "#454545" : "#3b3b3b")
        border.color: UIStyle.accentLightColor //"#2d97ff"
        border.width: root.activeFocus ? 2 : 0
        radius: root.height/2

        Item{
            width: parent.height

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Image{
                id: findImg
                width: parent.width*0.4
                height: width
                anchors.centerIn: parent

                source: "../icons/edit-find-symbolic.svg"
                sourceSize: Qt.size(width,height)
            }
        }
    }
}
