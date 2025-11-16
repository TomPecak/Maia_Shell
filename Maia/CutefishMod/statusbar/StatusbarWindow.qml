import QtQuick

import Maia.Client

Window {
    id: statusbarWindow

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
        anchors.fill: parent
    }
}
