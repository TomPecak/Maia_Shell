import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import "../contents"

Window {
    id: root
    flags:  Qt.Popup //Qt.WindowStaysOnTopHint | Qt.WA_TranslucentBackground | Qt.FramelessWindowHint

    width: 380
    height: 478

    color: "#00000000"

    visible: true
    modality: Qt.NonModal

    signal logoutClicked()
    signal turnoffClicked()

    onVisibleChanged:{
        if(root.visible === false){
            appMenuContent.resetState()
        }
    }

    AppMenuContent{
        id: appMenuContent
        onHideRequest:{
            root.visible = false
            appMenuContent.resetState()
        }
        onLogoutClicked: {
            root.logoutClicked()
        }
        onTurnoffClicked: {
            root.turnoffClicked()
        }
    }
}


