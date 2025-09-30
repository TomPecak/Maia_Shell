import QtQuick
import Maia.Client
import "../contents"

Window {
    id: root
    //flags:  Qt.Popup
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "pink"
    visible: true
    height: 100
    width: 100

    modality: Qt.NonModal

    // Component.onCompleted: {
    //     MWindowManagerX11.hideFromTaskbar(root, true);
    //     MWindowManagerX11.hideFromSwitcher(root, true);
    //     MWindowManagerX11.hideFromPager(root, true);
    // }

    Timer {
        id: initTimer
        interval: 3*128 //Wait 3 seconds to ensure KWin has started, initialize KWin effects.
        running: true
        repeat: false
        onTriggered: {
            MWindowManagerX11.hideFromTaskbar(root, true);
            MWindowManagerX11.hideFromSwitcher(root, true);
            MWindowManagerX11.hideFromPager(root, true);
        }
    }

    AppLauncherContent{
        anchors.fill: parent
        onAppLaunched: {
            root.visible = false
        }
    }
}
