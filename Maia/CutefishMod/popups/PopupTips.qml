import QtQuick
import QtQuick.Controls

import "../FishUI" as FishUI

Window {
    id: control
    visible: false

    color: "transparent"

    property string popupText
    property point position: Qt.point(0,0)
    property alias backgroundOpacity: _background.opacity
    property alias backgroundColor: _background.color
    property var borderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.3)
                                                    : Qt.rgba(0, 0, 0, 0.2)
    // Tracks the number of elements (e.g., AppItem) requesting to show the tooltip; tooltip remains visible as long as referenceCount > 0, preventing it from hiding during rapid mouse movement between elements
    property int referenceCount: 0

    flags: Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus | Qt.ToolTip
    width: label.implicitWidth + FishUI.Units.largeSpacing * 1.5
    height: label.implicitHeight + FishUI.Units.largeSpacing * 1.5


    Rectangle{
        id: _background

        anchors.fill: parent
        color: FishUI.Theme.secondBackgroundColor
        radius: FishUI.Theme.mediumRadius
        border.color: control.borderColor
        //border.color: "red"
        border.width: 1 / Screen.devicePixelRatio
        border.pixelAligned: Screen.devicePixelRatio > 1 ? false : true

        Behavior on color {
            ColorAnimation {
                duration: control.animationEnabled ? 200 : 0
                easing.type: Easing.Linear
            }
        }

    }

    Label{
        id: label
        anchors.centerIn: parent
        text: control.popupText
        color: FishUI.Theme.textColor
        // Rectangle{
        //     anchors.fill: parent
        //     color: "transparent"
        //     border.color: "green"
        //     border.width: 1
        // }
    }

    onPositionChanged: adjustCorrectLocation()

    function adjustCorrectLocation() {
        var posX = control.position.x
        var posY = control.position.y

        // left
        if (posX <= Screen.virtualX)
            posX = Screen.virtualX + 6

        // top
        if (posY <= Screen.virtualY)
            posY = Screen.virtualY + 6

        // right
        if (posX + control.width > Screen.virtualX + Screen.width)
            posX = Screen.virtualX + Screen.width - control.width - 1

        // bottom
        if (posY > control.height > Screen.virtualY + Screen.width)
            posY = Screen.virtualY + Screen.width - control.width - 1

        control.x = posX
        control.y = posY
    }

    function pshow() {
        if (control.popupText)
            referenceCount++
        control.show()
    }

    function phide() {
        control.hide()
        if(referenceCount > 0){
            referenceCount--;
        }

        if(referenceCount > 0){
            control.show()
        }

    }
}
