import QtQuick
import QtQuick.Controls
import "../"
import Maia.Backend


// WindowOverlay{

// }


Window {
    id: root
    objectName: "wind1"

    title: qsTr("Wallpaper window")
    visibility: Window.FullScreen
    width: Screen.width
    height: Screen.height
    visible: true
    color: "pink"
    flags: Qt.WindowStaysOnBottomHint

    Component.onCompleted: {
        backend.setX11WindowTypeAsDesktop(root)
    }

    WindowOverlay{

    }
}


