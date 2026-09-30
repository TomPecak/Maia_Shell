import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import ".."
import "../launcher"

Window {
    id: launcherWindow
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "white"
    visible: false
    height: 640
    width: 480

    LauncherContent{
        anchors.fill: parent

        onHideRequest: {
            console.log("CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCc")
            launcherWindow.visible = false
        }
    }
}















































