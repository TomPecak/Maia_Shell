import QtQuick

Window {
    id: control
    visible: false
    color: "transparent"

    property string popupText
    property point position: Qt.point(0,0)
    property alias backgroundOpacity: _background.opacity
    property alias backgroundColor: _background.color

    Rectangle{
        id: _background
    }

}
