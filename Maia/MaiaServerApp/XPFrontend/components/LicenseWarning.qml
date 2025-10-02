import QtQuick
import QtQuick.Controls
import QtCore

Image {
    id: root
    property real scaleFactor: 1.0

    height: 248 * scaleFactor
    width: 448 * scaleFactor

    source: "qrc:/assets/images/license_warning.svg"

    // Settings to save dontShowAgain variable
    Settings {
        id: settings
        category: "LicenseWarning"
        property bool dontShowAgain: false // Default false, componet will be visible
    }

    // Przy inicjalizacji sprawdzamy zapisane ustawienia
    Component.onCompleted: {
        root.visible = !settings.dontShowAgain // Ukryj, jeśli dontShowAgain jest true
    }

    Button {
        id: okButton
        text: qsTr("OK")
        anchors.topMargin: 10
        anchors.top: root.bottom
        anchors.right: root.right

        height: 40
        width: 100
        hoverEnabled: true

        property color btnColor: hovered ? "#f7d166" : "#f4c328"

        Behavior on btnColor {
            ColorAnimation {
                duration: 100
            }
        }

        background: Rectangle {
            color: okButton.btnColor
            radius: 10
            Rectangle {
                anchors.fill: parent
                anchors.margins: 5
                radius: parent.radius - anchors.margins
                color: okButton.btnColor
                border.width: 2
                border.color: "#000000"
            }
        }
        onPressed: {
            root.visible = false // Tylko ukrywa komponent
        }
    }

    Button {
        id: dontShowAgainButton
        text: qsTr("Don't show again")

        anchors.top: okButton.top
        anchors.rightMargin: 10
        anchors.right: okButton.left

        height: 40
        width: 200
        hoverEnabled: true

        property color btnColor: hovered ? "#f7d166" : "#f4c328"

        Behavior on btnColor {
            ColorAnimation {
                duration: 100
            }
        }

        background: Rectangle {
            color: dontShowAgainButton.btnColor
            radius: 10
            Rectangle {
                anchors.fill: parent
                anchors.margins: 5
                radius: parent.radius - anchors.margins
                color: dontShowAgainButton.btnColor
                border.width: 2
                border.color: "#000000"
            }
        }
        onPressed: {
            settings.dontShowAgain = true // Zapisuje ustawienie
            root.visible = false // Ukrywa komponent
        }
    }
}
