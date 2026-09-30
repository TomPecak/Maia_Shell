import QtQuick

import QtQuick.Layouts

import Maia.Backend

import "." as FishUI

MMenuPopupWindow {
    id: control

    default property alias content : _mainLayout.data

    Rectangle {
        id: _background
        anchors.fill: parent
        color: FishUI.Theme.secondBackgroundColor
        radius: FishUI.Theme.hugeRadius
        opacity: 0.6
        border.color: _background.borderColor
        border.width: 1 / FishUI.Units.devicePixelRatio
        border.pixelAligned: FishUI.Units.devicePixelRatio > 1 ? false : true

        property var borderColor: FishUI.Theme.darkMode ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(0, 0, 0, 0.2)


        MWindowBlur {
            window: control
            geometry: Qt.rect(control.x, control.y, control.width, control.height)
            windowRadius: _background.radius
            enabled: true
        }
    }




    ColumnLayout {
        id: _mainLayout
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
    }

    function open() {
        control.show()
    }

    function popup() {
        control.show()
    }
}
