import QtQuick
import QtQuick.Effects

import Maia.Backend

import "../FishUI" as FishUI

Item {
    id: control

    property bool isLeft: false
    property bool isRight: false
    property bool isBottom: true

    property var iconSize: control.height * iconSizeRatio

    property alias icon: icon
        property alias mouseArea: iconArea

    property bool enableActivateDot: true
    property bool isActive: false

    property var popupText

    property double iconSizeRatio: 0.8
    property var iconName

    property bool dragStarted: false

    signal positionChanged()
    signal released()
    signal pressed(var mouse)
    signal pressAndHold(var mouse)
    signal clicked(var mouse)
    signal rightClicked(var mouse)
    signal doubleClicked(var mouse)
    signal dropped(var drop)

    MIconItem{
        id: icon
        anchors.centerIn: parent
        width: control.iconSize
        height: control.iconSize
        source: iconName


        //visible: false // Hide the source item to avoid rendering both
        layer.enabled: true

            layer.effect: MultiEffect {
                id: iconColorize
                anchors.fill: icon
                source: icon
                colorizationColor: "#000000" // Same color as ColorOverlay
                colorization: iconArea.pressed && !mouseArea.drag.active ? 0.4 : 0
            }

        // Rectangle{
        //     anchors.fill: parent
        //     color: "transparent"
        //     border.width: 1
        //     border.color: "green"

        //     Text{
        //         anchors.centerIn: parent

        //         text: "P:" + popupText
        //         //text: windowName

        //         //text: model.windowIcon
        //         //text: "dupa"
        //     }
        // }


    }

    MouseArea{
        id: iconArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.axis: Drag.XAndYAxis

        onClicked: {
            if(mouse.button === Qt.RightButton)
                control.rightClicked(mouse)
            else
                control.clicked(mouse)

        }

        onPressed: {
            control.pressed(mouse)
            console.log("popupTips.hide()")
            popupTips.phide()
        }

        onPositionChanged: {
            control.positionChanged()
        }

        onPressAndHold: control.pressAndHold(mouse)

        onReleased: {
            control.released()
        }

        onContainsMouseChanged: {
            if(containsMouse && control.popupText !== ""){
                popupTips.popupText = control.popupText
                popupTips.position = Qt.point(control.mapToGlobal(0, 0).x + (control.width / 2 - popupTips.width / 2), control.mapToGlobal(0, 0).y - popupTips.height - 6)
                console.log("popupTips.show()")
                popupTips.pshow()
            }else{
                console.log("popupTips.hide()")
                popupTips.phide()
            }
        }
    }

    Rectangle{
        id: activeRect

        property var leftX: 2
        property var leftY: (parent.height - height) / 2

        property var bottomX: (parent.width - width) / 2
        property var bottomY: icon.y + icon.height + activeRect.height / 2 - 1

        property var rightX: icon.x + icon.width + activeRect.width / 2 - 1
        property var rightY: (parent.height - height) / 2

        property var circleSize: isBottom ? control.height * 0.06 : control.width * 0.06
        property var activeLength: isBottom ? control.height * 0.5 : control.height * 0.5

        width: !isBottom ? circleSize : (isActive ? activeLength : circleSize)
        height: !isBottom ? (isActive ? activeLength : circleSize) : circleSize
        radius: !isBottom ? width / 2 : height / 2
        visible: enableActivateDot && !dragStarted
        color: FishUI.Theme.textColor

        x: isLeft ? leftX : isBottom ? bottomX : rightX
        y: isLeft ? leftY : isBottom ? bottomY : rightY

        Behavior on width {
            NumberAnimation {
                duration: isBottom ? 250 : 0
                easing.type: Easing.InOutSine
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: !isBottom ? 250 : 0
                easing.type: Easing.InOutSine
            }
        }
    }
}
