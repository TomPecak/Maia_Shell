import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import "../contents"

Popup{
    id: root

    popupType: Popup.Window

    width: 380
    height: 478

    topPadding: 0
    rightPadding: 0
    bottomPadding: 0
    leftPadding: 0

    closePolicy: Popup.CloseOnPressOutside

    visible: true

    signal logoutClicked()
    signal turnoffClicked()

    onVisibleChanged:{
        if(root.visible === false){
            appMenuContent.resetState()
        }
    }

    background: Rectangle {
            color: "transparent"
    }

    contentItem: AppMenuContent{
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


