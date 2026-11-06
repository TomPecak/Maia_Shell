import QtQuick
import QtQuick.Controls
import Maia.Backend

Window {
    id: root
    title: "Clock3DWindow"
    width: 200
    height: 200
    visible: true

    flags: Qt.WA_TranslucentBackground | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint

    color: "#00000000"

    Clock3DContent{
        anchors.fill: parent
    }
}
