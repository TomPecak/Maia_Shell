import QtQuick

DockItem {
    id: appItem

    property var windowCount: model.windowCount
    property var dragSource: null

    enableActivateDot: windowCount !== 0


    onClicked: {
        if(mouse.button === Qt.LeftButton){
            appModel.clicked(model.appId)
        }
    }
}
