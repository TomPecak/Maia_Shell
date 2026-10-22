import QtQuick
import QtQuick.Controls
import XPLunaFrontend

Popup {
    popupType:  Popup.Window

    width: 81
    height: 136

    contentItem: SystemVolumeContent{
        anchors.fill: parent
    }
}
