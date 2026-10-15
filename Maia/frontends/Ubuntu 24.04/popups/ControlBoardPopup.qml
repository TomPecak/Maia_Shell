import QtQuick
import QtQuick.Controls
import ".."
import "../contents"

Popup{
    id: root
    //flags:  Qt.Popup
    //color: "red"
    width: 370
    height: 327
    padding: 0
    topPadding: 19
    bottomPadding: 19
    leftPadding: 19
    rightPadding: 19

    popupType: Popup.Window


    Behavior on height{
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad


        }
    }


    contentItem: ControlBoardContent{
        anchors.fill: parent
    }

    background:  null

    // background: Rectangle{
    //     //color: "#fafafa"
    //     color: "#FFFFFF"
    //     anchors.fill: parent
    //     border.width: 1
    //     border.color: "#dedede"
    //     radius: 15
    // }
}
