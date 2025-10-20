import QtQuick

import Maia.Client

import "../contents"

Window {
    id: root
    //flags: Qt.Popup //grab mouse events
    flags: Qt.Window | Qt.FramelessWindowHint //| Qt.X11BypassWindowManagerHint

    Component.onCompleted: {
        backend.setX11WindowTypeAsDock(root);
    }

    width: dockContent.width
    height: dockContent.height

    color: "transparent"

    MWindowBlur {
        window: root
        geometry: Qt.rect(root.x, root.y, root.width, root.height)
        windowRadius: dockContent.windowRadius
        enabled: true
    }

    DockContent{
        id: dockContent
    }
}
