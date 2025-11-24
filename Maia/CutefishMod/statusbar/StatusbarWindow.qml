import QtQuick

import Maia.Client

Window {
    id: statusbarWindow

    property alias wallpaperUrl: statusbarContent.wallpaperUrl

    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"

    height: 25

    Component.onCompleted: {
        backend.setX11WindowTypeAsDock(statusbarWindow);
    }

    MWindowBlur {
        window: statusbarWindow
        enabled: true
    }

    StatusbarContent{
        id: statusbarContent
        anchors.fill: parent

        windowX: statusbarWindow.x
        windowY: statusbarWindow.y
        windowWidth: statusbarWindow.width
        windowHeight: statusbarWindow.height
    }
}
