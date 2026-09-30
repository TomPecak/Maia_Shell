import QtQuick
import QtQuick.Controls

Menu {
    id: contextMenu
    implicitWidth: 127
    //implicitHeight: 40
    topPadding: 3
    leftPadding: 3
    rightPadding: 3
    bottomPadding: 3

    popupType: Popup.Window
    //popupType: Popup.Native
    //popupType: Popup.Item
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    property bool active: true

    delegate: XPMenuItem{
        id: delegateItem
        Binding{
            delegateItem.active: contextMenu.active
        }
    }

    background: Rectangle{
        color: "#ffffff"

        //implicitWidth: 127
        //implicitHeight: 17

        border.width: 1
        border.color: "#aca899"
    }
}





