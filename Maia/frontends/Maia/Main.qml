import QtQuick

import Maia.Backend

Window{
    id: root

    visible: true

    width: Screen.width
    height: Screen.height
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    visibility: Window.FullScreen

    color: "yellow"

    MProxyWindow{
        id: appLauncherWindow
        source: "BottomLayer.qml"
        //source: Qt.resolvedUrl("./windows/AppsLauncherWindow.qml")
        proxyVisible: true
        anchors.right: parent.right
        //anchors.left: parent.left
        anchors.top: parent.top
        //anchors.bottom: parent.bottom
        // Rozmiar elementu = rozmiar okna proxy (nadpisuje width/height z BottomLayer.qml),
        // bez niego okno ma 0x0 i nie jest wyświetlane
        width: 100
        height: 100
        swapInterval: 1

        onProxyVisibleChanged: {
            console.log("9999999999999999 PROXY VISIBLE CHANGED !! proxyVisible = " + appLauncherWindow.proxyVisible)
        }
    }
}
