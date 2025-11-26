import QtQuick
import QtQuick.Controls
import Maia.Backend
import QtQuick3D
import "../"
import "../content"

Window {
    id: root
    objectName: "wind1"

    title: qsTr("Overlay window")
    //flags: Qt.WindowStaysOnTopHint
    visibility: Window.FullScreen
    width: Screen.width
    height: Screen.height
    visible: true
    //color: "#00000000"
    //color: "red"
    //color: "#88FFFFFF"
    color: "transparent"

    //color: "#88ffffff"

    // onActiveChanged: {
    //      if(root.active === false)
    //          appMenuContent.visible = false
    // }



    FontLoader {
        id: tahomaBold
        source: "../assets/fonts/tahomabd.ttf"
    }

    FontLoader {
       id: tahomaRegular
        source: "../assets/fonts/tahoma.ttf"
    }

    onActiveFocusItemChanged: {
        if(root.activeFocusItem === null)
            appMenuContent.visible = false
    }

    Component.onCompleted: {
        //backend.setX11WindowTypeAsTopMenu(root)
        backend.setX11WindowTypeAsNotification(root)
    }

    Rectangle{
        id: backgroundRect
        anchors.fill: parent
        color: "#99FFFF00"
        visible: visibleBackgroundCheckbox.checked
    }

    MouseArea{
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => {
                       if (mouse.button === Qt.RightButton) {
                           wallpaperContextMenu.popup(mouse.x, mouse.y)
                       }
                   }
    }

    Menu {
        id: wallpaperContextMenu
        implicitHeight: 129
        popupType: Popup.Item
        closePolicy: Popup.CloseOnPressOutside

        MenuItem { text: "Cut" }
        MenuItem { text: "Copy" }
        MenuItem { text: "Paste" }
    }




    // Rectangle {
    //     width: 320
    //     height: 480
    //     color: "steelblue"

    //     ListView {
    //         anchors.fill: parent
    //         //! [model]
    //         model: Qt.fontFamilies()
    //         //! [model]

    //         delegate: Item {
    //             height: 40
    //             width: ListView.view.width
    //             required property string modelData
    //             Text {
    //                 anchors.centerIn: parent
    //                 text: parent.modelData
    //                 //! [delegate]
    //                 font.family: parent.modelData
    //                 //! [delegate]
    //                 font.pixelSize: 20
    //                 color: "white"
    //             }
    //         }
    //     }
    // }

    CheckBox{
        id: dbgMenu
        anchors.left: parent.left
        anchors.top: parent.top
        //text: "Debug menu"

        Component.onCompleted: {
            backend.addMaskedItem(dbgMenu)
        }
    }

    MMaskedItem{
        id: dbgPanelMask
        width: 150
        height:300
        anchors.right: parent.right
        anchors.top: parent.top
        visible: dbgMenu.checked
        enabled: dbgMenu.checked

        Rectangle{
            anchors.fill: parent
            color: "green"
        }

        Column{
            id: buttonsRow

            Button{
                text: "Logout"
                onPressed: {
                    MSessionManager.logout()
                }
            }

            CheckBox{
                id: maskBackgroundCheckbox
                text: "Mask Background"

            }
            CheckBox{
                id: visibleBackgroundCheckbox
                text: "Visible Backgroun"
            }


            MenuSeparator{

            }

            CheckBox{
                id: orangeShowCheckbox
                text: "Orange show"
            }

            MenuSeparator {
            }

            CheckBox{
                id: blueShowCheckbox
                text: "Blue show"
            }

            CheckBox{
                id: blueAnimationCheckbox
                text: "Blue animation"
            }


            Button{
                text: "Qt.quit()"
                onClicked: {
                    Qt.quit()
                }
            }
        }
    }


    // MMaskedItem{
    //     x: draggableRect.x
    //     y: draggableRect.y
    //     width: draggableRect.width
    //     height: draggableRect.height
    //     visible: orangeShowCheckbox.checked
    //     enabled: orangeShowCheckbox.checked
    // }




























}
