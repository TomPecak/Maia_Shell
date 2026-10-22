import QtQuick
import GnomeFrontend
import ".."

Rectangle{
    id: topPanel

    implicitWidth: 500
    implicitHeight: 29
    color: UIStyle.colorTopPanelBackground
    visible: true

    signal clicked()
    property bool controlBoardVisible: false

    Text{
        id: dateTimeText
        anchors.centerIn: parent
        font.family: "Noto Sans"
        font.pointSize: 10
        text: Qt.formatDateTime(new Date(), "d MMM  hh:mm")
        color: "#FFFFFF"

        Timer {
            interval: 10000 // Refresh time 10s
            running: true
            repeat: true
            onTriggered: {
                dateTimeText.text = Qt.formatDateTime(new Date(), "d MMM  hh:mm")
            }
        }
    }

    Rectangle{
        id: statusArea
        width: statusRow.width
        height: 23
        radius: 12
        anchors.verticalCenter : parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 3
        //color: "#43FFFFFF"
        //color: "#28FFFFFF"
        color: controlBoardVisible ? ("#43FFFFFF") : (statusMouseArea.containsMouse ? "#28FFFFFF" : UIStyle.colorTopPanelBackground)
        //color: statusMouseArea.containsMouse ? (controlBoard.visible ? ("#43FFFFFF") : ("#28FFFFFF")) : (controlBoard.visible ? ("#43FFFFFF") : ( UIStyle.colorTopPanelBackground))

        // Behavior on color {
        //     ColorAnimation {
        //         duration: 100
        //     }
        // }

        Row{
            id: statusRow
            height: parent.height
            anchors.right: parent.right
            anchors.verticalCenter : parent.verticalCenter
            spacing: 13
            leftPadding: 13
            rightPadding: 13

            // Image{
            //     height: 15
            //     width: 15
            //     source: "../../assets/images/network-wireless-connected-symbolic-light.svg"
            //     sourceSize.height: height
            //     sourceSize.width: width
            //     anchors.verticalCenter : parent.verticalCenter
            // }
            Image{
                height: 15
                width: 15
                source: "../../assets/images/network-wireless-connected-symbolic-light.svg"
                sourceSize.height: height
                sourceSize.width: width
                anchors.verticalCenter : parent.verticalCenter
            }

            Image{
                height: 15
                width: 15
                source: "../../assets/images/bluetooth-active-symbolic-light.svg"
                sourceSize.height: height
                sourceSize.width: width
                anchors.verticalCenter : parent.verticalCenter
            }
            Image{
                height: 15
                width: 15
                source: "../../assets/images/audio-volume-high-symbolic-light.svg"
                sourceSize.height: height
                sourceSize.width: width
                anchors.verticalCenter : parent.verticalCenter
            }
            Image{
                height: 15
                width: 15
                source: "../../assets/images/battery-level-100-symbolic-light.svg"
                sourceSize.height: height
                sourceSize.width: width
                anchors.verticalCenter : parent.verticalCenter
            }
        }
        MouseArea{
            id: statusMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                topPanel.clicked()
            }
        }
    }
}
