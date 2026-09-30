import QtQuick
import QtQuick3D

View3D {
    id: root
    implicitWidth: 200
    implicitHeight: 200
    focusPolicy: Qt.NoFocus

    Text {
        id: timeDisplay3D
        anchors.fill: parent

        text: "Maia"
        //text: Qt.formatTime(new Date(), "h:mm")
        font.pointSize: width*0.29
        font.family: "NeverMind Handwriting"
        font.styleName: "Medium"
        color: "#FFFFFFFF"
        visible: false
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Timer {
            interval: 10000
            running: false
            //running: true
            repeat: true
            onTriggered: {
                timeDisplay3D.text = Qt.formatTime(new Date(), "h:mm")
            }
        }
    }

    PerspectiveCamera {
        position: Qt.vector3d(0, 0, 170)
    }

    DirectionalLight {
        eulerRotation.x: -10
    }

    Model {
        id: cube
        source: "#Cube"

        materials: DefaultMaterial {
            diffuseColor: Qt.rgba(1, 1, 1, 1)
            diffuseMap: Texture {
                sourceItem: timeDisplay3D
                //source: "qt_logo.png"
            }
        }

        eulerRotation.y: 90

        Vector3dAnimation on eulerRotation {
            loops: Animation.Infinite
            //loops: 1
            duration: 5000
            from: Qt.vector3d(0, 0, 0)
            to: Qt.vector3d(360, 0, 360)
        }
    }
}

