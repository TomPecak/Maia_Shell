import QtQuick
import "../contents"

Window {
    id: root
    flags: Qt.Popup

    width: content.width
    height: content.height

    color: "#00000000"

    ControlBoardContent{
        id: content
    }
}
