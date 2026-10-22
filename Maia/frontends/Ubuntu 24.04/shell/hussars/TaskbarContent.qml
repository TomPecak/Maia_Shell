import QtQuick
import QtQuick.Effects
import Maia.Backend

Rectangle {
    implicitHeight: 35
    color: "white"
    radius: 5

    Rectangle{
        id: appsButton

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        implicitWidth: 3*parent.height

        topLeftRadius: 5
        bottomLeftRadius: 5

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#d22628" }
            GradientStop { position: 1.0; color: "#540004" }
        }

        Text{
            anchors.centerIn: parent
            color: "white"
            font.pointSize: parent.height*0.5
            text: qsTr("Maia")
            font.bold: true

            style: Text.Raised
            styleColor: "#550000"
        }
    }

    MTaskbarModel{
        id: taskbarModel
    }

    Row{
        anchors.left:  appsButton.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 5
        anchors.bottomMargin: 5
        anchors.leftMargin: 5
        spacing: 10


        Repeater{
            id: taskbarRepeater
            model: taskbarModel

            Rectangle{
                implicitHeight: parent.height
                width: 5*height
                radius: 5
                 property bool activeWindow : model.windowActive
                color: activeWindow ? "#555555" : "black"

                //border.width: 1
                //border.color: "black"



                Image{
                    id: appIcon
                    width: 16
                    height: 16
                    source: model.windowIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(width,height)
                }

                Text{
                    anchors.left: appIcon.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    text: model.windowName
                    font.pointSize: parent.height*0.3
                    font.bold: true
                    clip: true
                    color: "white"
                    verticalAlignment:  Text.AlignVCenter

                }
            }

        }
    }

    Text{
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 15
        text: "14:52"
        color: "red"
        //font.family: "NeverMind Handwriting"
        font.family: "CNN"
        font.pointSize: parent.height*0.7

        layer.enabled: true
        // For the layered items, you can assign a MultiEffect directly
        // to layer.effect.
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.4
            shadowHorizontalOffset: 2.4
            shadowOpacity: 0.5
            shadowScale: 1.0
            shadowVerticalOffset: 2.4
        }
    }
}
