import QtQuick
import org.kde.kirigami as Kirigami

import MaiaFrontend

// One application in the App Library: icon and name below it.
//
// Under the pointer the cell gets the highlight of iPadOS and the icon lifts slightly; pressed, the
// icon sinks. The keyboard selection is a ring in the accent color (the focus ring of iPadOS). The
// name may take two lines: Linux application names are long ("LibreOffice Writer"), and the name
// is what tells similar icons apart.
Item {
    id: item

    property string name
    property string iconName
    // Selected with the keyboard: Enter launches it
    property bool selected: false

    signal clicked()

    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.onPressAction: item.clicked()

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 16
        color: mouseArea.pressed ? Theme.pressed
             : mouseArea.containsMouse || item.selected ? Theme.hover
             : "transparent"
        border.width: item.selected ? 2 : 0
        border.color: Theme.accent

        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    Kirigami.Icon {
        id: icon

        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        width: 60
        height: 60
        source: item.iconName
        fallback: "application-x-executable"
        scale: mouseArea.pressed ? 0.9 : mouseArea.containsMouse ? 1.06 : 1

        Behavior on scale {
            ScaleAnimator { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    Text {
        anchors.top: icon.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 16
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: item.name
        color: Theme.label
        font.pixelSize: 12
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        anchors.margins: 4
        hoverEnabled: true
        onClicked: item.clicked()
    }
}
