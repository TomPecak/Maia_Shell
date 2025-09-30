import QtQuick
import QtQuick.Controls
import Maia.Client
import "../style"

Rectangle{
    id: root
    color: "#222222"
    width: 800
    height: 600
    //flags: /*Qt.BypassWindowManagerHint |*/ Qt.FramelessWindowHint

    signal appLaunched()

    FontLoader {
        id: notoSansRegular
        source: "../fonts/NotoSans-Regular.ttf"
    }

    MFavoritesAppsModel{
    id: favoriteAppsModel
    }

    GTextField {
        id: searchField
        placeholderText: "Search"

        height: 42
        width: 340

        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.rightMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter

        onTextChanged: {
            appsListModel.setFilterFixedString(searchField.text);
        }
    }


    GridView {
        id: appsGridView
        anchors.top: searchField.bottom
        anchors.topMargin: 20
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: margins
        anchors.rightMargin: margins
        model: appsListModel
        clip: true
        cellWidth: 181
        cellHeight: 181
        //cacheBuffer: 2147483647 - The cache with a high value has been disabled, performance issues arise with using the proxy model and application search, and there was an issue with displaying delegates in the grid view layout.

        property int margins: (root.width - 6*cellWidth)/2
        property int createdDelegates: 0

        delegate: Item {
            id: appDelegate
            width: appsGridView.cellWidth
            height: appsGridView.cellHeight

            Component.onCompleted: {
                appsGridView.createdDelegates++;
                //console.log("created delegates: " + appsGridView.createdDelegates)
            }


            required property string name
            required property string icon
            required property string exec
            required property string id

            Rectangle {
                width: 145
                height: 145
                anchors.centerIn: parent
                color: appRectMouseArea.containsMouse ? ("#343434") : ("#222222")
                radius: 12

                Image{
                    id: appImage
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    source: "image://backend_app_icon/" + appDelegate.icon
                    width: 96
                    height: 96
                    sourceSize.height: 96
                    sourceSize.width: 96
                    cache: true
                    //asynchronous: true
                }

                Text{
                    anchors.top: appImage.bottom
                    anchors.topMargin: 11
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.left: parent.left
                    anchors.leftMargin:12

                    text: appDelegate.name
                    font.family: "Noto Sans"
                    font.pointSize: 11
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }

                MouseArea{
                    id: appRectMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: (mouse)=> {
                                   if (mouse.button === Qt.LeftButton){
                                       root.appLaunched()
                                       backend.runCommand(exec)
                                   }
                               }
                    onPressed: (mouse)=> {
                                   if (mouse.button === Qt.RightButton){
                                       contextMenu.showMenu(appDelegate.id)
                                   }
                               }
                }
            }
        }
    }

    GMenu{
        id: contextMenu

        width: 209

        property string app_id

        GMenuItem{
            active: false
            text: qsTr("New Window")
        }

        GMenuSeparator{
        }

        GMenuItem{
            text: qsTr("Pin to Dash")
            onTriggered: {
                favoriteAppsModel.addFavorite(contextMenu.app_id);
            }
        }

        GMenuSeparator{
        }

        GMenuItem{
            active: false
            text: qsTr("App Details")
        }

        function showMenu(id){
            console.log("show Menu = " + id)
            contextMenu.app_id = id
            popup()
        }
    }
}
