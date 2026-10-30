import QtQuick

import Maia.Backend

Window{
    id: root

    visible: true

    title: "root"

    width: 500
    height: 500
    flags: Qt.Window// | Qt.FramelessWindowHint
    //visibility: Window.FullScreen





    color: "yellow"

    MProxyWindow{
        id: topLayer
        source: "LayerTop.qml"

        proxyVisible: true
        anchors.right: parent.right
        //anchors.left: parent.left
        anchors.top: parent.top
        //anchors.bottom: parent.bottom

        // The size the server gives the window of the dock at start. It is anchored to three
        // edges only (LayerTop.qml), so the compositor uses this size along the fourth one:
        // it has to be the whole screen.
        width: Screen.width
        height: Screen.height
        swapInterval: 1

        onProxyVisibleChanged: {
            console.log("9999999999999999 PROXY VISIBLE CHANGED !! proxyVisible = " + appLauncherWindow.proxyVisible)
        }
    }

    MProxyWindow{
        id: bottomLayer
        source: "LayerBottom.qml"

        proxyVisible: true
        anchors.right: parent.right
        //anchors.left: parent.left
        anchors.top: parent.top
        //anchors.bottom: parent.bottom

        width: 100
        height: 100
        swapInterval: 1

        onProxyVisibleChanged: {
            console.log("9999999999999999 PROXY VISIBLE CHANGED !! proxyVisible = " + appLauncherWindow.proxyVisible)
        }
    }

    AvailableFonts{
        anchors.right: root.right
        anchors.bottom: root.bottom
    }
}
