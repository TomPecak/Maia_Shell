import QtQuick
import QtQuick.Layouts

import LumenFrontend
import Maia.Network

// A QR code on white (phones need the contrast, also in the dark theme) with the network's name
// and password beside it, for sharing (docs #15) and the running hotspot (#16).
RowLayout {
    id: card

    property var code: null      // { text, size, modules } from NetworkControl.qrCode
    property string name
    property string security
    property string password
    property bool loading: false

    spacing: Theme.spacingXL
    Layout.fillWidth: true

    Rectangle {
        implicitWidth: 196
        implicitHeight: 196
        radius: Theme.radiusMedium
        color: "white"
        Layout.alignment: Qt.AlignTop

        QrCodeView {
            anchors.fill: parent
            anchors.margins: 4
            quietZone: 2
            moduleCount: card.code ? card.code.size : 0
            modules: card.code ? card.code.modules : new ArrayBuffer(0)
            Accessible.name: qsTr("QR code of the network %1").arg(card.name)
        }

        ProgressRing {
            visible: card.loading
            anchors.centerIn: parent
            width: 28
            height: 28
            value: 0.25
            RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: card.loading }
        }
    }

    ColumnLayout {
        spacing: Theme.spacingM
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop

        LText {
            text: qsTr("Scan with a phone's camera to connect")
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Repeater {
            model: [{ label: qsTr("Network name"), value: card.name },
                    { label: qsTr("Security"), value: card.security },
                    { label: qsTr("Password"), value: card.password }]

            ColumnLayout {
                required property var modelData

                visible: modelData.value.length > 0
                spacing: 2
                Layout.fillWidth: true

                LText {
                    text: modelData.label
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textSecondary
                }

                // Selectable, to copy it
                TextEdit {
                    text: modelData.value
                    readOnly: true
                    selectByMouse: true
                    color: Theme.textPrimary
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontBodyLarge
                    wrapMode: TextEdit.WrapAnywhere
                    Layout.fillWidth: true
                }
            }
        }
    }
}
