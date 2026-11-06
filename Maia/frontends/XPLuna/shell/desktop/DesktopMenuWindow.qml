import QtQuick
import QtQuick.Controls
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

import XPLunaFrontend

// The desktop's context menu, over everything (overlay layer).
//
// A menu of the desktop itself (background layer) would open under the windows, so it lives in
// this transparent full-screen surface, shown only while the menu is open. A click beside the menu
// closes it, as does Escape.
Window {
    id: root

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: recentAppsContextMenu.visible || d.opening

    LayerShell.Window.scope: "xpluna-desktop-menu"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // The coordinates of the desktop, under the taskbar too
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    // Opens the menu at a point of the desktop
    function openAt(x, y) {
        d.opening = true
        recentAppsContextMenu.popup(x, y)
        d.opening = false
    }

    QtObject {
        id: d
        // Keeps the window shown while the menu is being opened
        property bool opening: false
    }

    // A click beside the menu (the menu closes itself on it) lets the window go
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: recentAppsContextMenu.visible
    }

    MFrontendModel{
        id: frontendManager
    }

    XPMenu {
        id: recentAppsContextMenu
        //width: 127
        //height: 135 + 17
        // Inside this window, which is above everything
        popupType: Popup.Item

        XPMenuItem {
            text: qsTr("Arrange Icons By")
            active: false
            onTriggered: {
            }
        }

        XPMenuItem {
            text: qsTr("Refresh")
            active: false
        }

        XPMenu {
            id: frontendSubmenu
            title: qsTr("Change Frontend")
            //height: 40
            enabled: frontendsInstantiator.count > 0

            Instantiator {
                id: frontendsInstantiator
                model: frontendManager
                delegate: XPMenuItem {
                    text: model.frontendName
                    active: !model.frontendActive
                    onTriggered: {
                        console.log("1-- onTrigger() new frontend = " + model.frontendId)
                        frontendManager.activeFrontend = model.frontendId
                    }
                }

                onObjectAdded: (index, object) => frontendSubmenu.insertItem(index, object)
                onObjectRemoved: (index, object) => frontendSubmenu.removeItem(object)
            }
        }

        XPMenuSeparator{
        }

        XPMenuItem {
            text: "Paste"
            active: false
        }

        XPMenuItem {
            text: "Paste Shortcut"
            active: false
        }

        XPMenuSeparator{
        }

        XPMenuItem {
            text: "New"
            active: false
        }

        // XPMenu {
        //     title: "New"
        //     //active: false
        //     //     Action { text: "Find Next" }
        //     //     Action { text: "Find Previous" }
        //     //     Action { text: "Replace" }
        // }

        XPMenuSeparator{
        }

        XPMenuItem {
            text: "Properties"
            active: false
        }
    }
}
