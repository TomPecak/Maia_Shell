import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    width: 320
    height: 480
    color: "steelblue"

    ListView {
        anchors.fill: parent
        flickDeceleration: 0.0001
//! [model]
        model: Qt.fontFamilies()
//! [model]

        delegate: Item {
            height: 40
            width: ListView.view.width
            required property string modelData
            Text {
                anchors.centerIn: parent
                text: parent.modelData
//! [delegate]
                font.family: parent.modelData
//! [delegate]
                font.pixelSize: 20
                color: "white"
            }
        }
    }

    Button{
        anchors.right: root.right
        anchors.top: root.top
        onClicked: {
            root.visible = false;
        }
    }
}