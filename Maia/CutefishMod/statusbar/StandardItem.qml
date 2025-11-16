import QtQuick

import "../FishUI" as FishUI

Item {
    id: control

    property real moveX: 0
    property real moveY: 0

    property string popupText: ""

    property bool checked: false
    property bool animationEnabled: false

    property alias mouseArea: _mouseArea

    signal clicked(var mouse)
    signal pressed(var mouse)
    signal wheel(var wheel)
    signal contextMenu(var mouse)

    signal positionChanged
    signal released

    onCheckedChanged: {
        _bgRect.state = checked ? "shown" : "hidden"
    }

    MouseArea {
        id: _mouseArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true

        onEntered: {
            if (checked)
                return

            _bgRect.width = 0
            _bgRect.height = 0

            _bgRect.x = mouseX
            _bgRect.y = mouseY
            _bgRect.state = "shown"
        }

        onExited: {
            if (checked)
                return

            control.moveX = mouseX
            control.moveY = mouseY
            _bgRect.state = "hidden"
        }

        onClicked: {
            control.moveX = mouseX
            control.moveY = mouseY
            control.clicked(mouse)
        }

        onPressed: {
            popupTips.hide()
            control.pressed(mouse)
        }

        onWheel: {
            control.wheel(wheel)
            wheel.accepted = false
        }

        onReleased: {
            control.released()
        }

        onContainsMouseChanged: {
            if (containsMouse && control.popupText !== "") {
                popupTips.popupText = control.popupText
                popupTips.position = Qt.point(control.mapToGlobal(0, 0).x + (control.width / 2 - popupTips.width / 2),
                                              control.height + FishUI.Units.smallSpacing)
                popupTips.show()
            } else {
                popupTips.hide()
            }
        }

        onPositionChanged: {
            control.positionChanged()
        }
    }

    Rectangle {
        id: _bgRect
        radius: FishUI.Theme.smallRadius

        state: "hidden"
        states: [
            State {
                name: "shown"
                PropertyChanges {
                    target: _bgRect
                    x: 0
                    y: 1
                    width: control.width
                    height: control.height - 2
                    visible: true
                }
            },
            State {
                name: "hidden"
                PropertyChanges {
                    target: _bgRect
                    x: control.moveX
                    y: control.moveY
                    width: 0
                    height: 0
                    visible: false
                }
            }
        ]

        transitions:[
            Transition {
                from: "hidden"
                to: "shown"

                SequentialAnimation{
                    PropertyAnimation {
                        target: _bgRect
                        properties: "visible"
                        duration: 0
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        target: _bgRect
                        properties: "x, y, width, height"
                        duration: control.animationEnabled ? 400 : 0
                        easing.type: Easing.OutQuart
                    }
                }
            },
            Transition {
                from: "shown"
                to: "hidden"

                SequentialAnimation{
                    PropertyAnimation {
                        target: _bgRect
                        properties: "x, y, width, height"
                        duration: control.animationEnabled ? 200 : 0
                        easing.type: Easing.OutQuart
                    }
                    PropertyAnimation {
                        target: _bgRect
                        properties: "visible"
                        duration: 0
                        easing.type: Easing.OutQuart
                    }
                }
            }
        ]

        color: {
            if (control.checked) {
                return (rootItem.darkMode) ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(255, 255, 255, 0.2)
            }

            if (_mouseArea.containsPress)
                return (rootItem.darkMode) ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(255, 255, 255, 0.3)
            else
                return (rootItem.darkMode) ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(255, 255, 255, 0.2)
        }
    }
}
