import QtCore
import QtQuick
import QtQuick.Controls
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

import GnomeFrontend

// The desktop's context menu and the dialog it may open, over everything (overlay layer).
//
// A menu of the desktop itself (background layer) would open under the windows, so they live in
// this transparent full-screen surface, shown only while the menu or the dialog is open. A click
// beside the menu closes it, as does Escape.
Window {
    id: root

    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint
    visible: contextMenu.visible || warningDialog.visible || d.opening

    LayerShell.Window.scope: "ubuntu-desktop-menu"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // The coordinates of the desktop, under the panels too
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityOnDemand
    LayerShell.Window.activateOnShow: true

    // Opens the menu at a point of the desktop
    function openAt(x, y) {
        d.opening = true
        contextMenu.popup(x, y)
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
        enabled: contextMenu.visible
    }

    MFrontendModel{
        id: frontendManager
    }

    Settings {
        id: settings
        category: "ThemeInstallationWarning"
        property bool dontShowAgain: false // Default false – dialog will be visible on first switch
    }

    // Warning Dialog – shows only once, on first frontend switch
    Dialog {
        id: warningDialog
        title: qsTr("First Frontend Switch")
        standardButtons: Dialog.Ok | Dialog.Cancel
        modal: true
        parent: Overlay.overlay  // Uses Overlay for better positioning in fullscreen
        width: 400
        anchors.centerIn: parent
        property string pendingFrontendId: ""

        contentItem: Text {
            //width: warningDialog.availableWidth
            wrapMode: Text.WordWrap
            color: "red"
            font.bold: true
            text: qsTr("Welcome to Maia Shell! The first switch to a new frontend may take up to 5 minutes, " +
                       "as it installs icons, themes, and other resources. This is a one-time setup – " +
                       "please be patient and don't interrupt. Ready to proceed?")
        }

        onAccepted: {
            // Switch frontend and mark warning as shown
            frontendManager.activeFrontend = warningDialog.pendingFrontendId
            settings.dontShowAgain = true
            warningDialog.pendingFrontendId = ""  // Clear
        }

        onRejected: {
            // Cancel – do not switch, clear pending
            warningDialog.pendingFrontendId = ""
        }
    }

    GMenu {
        id: contextMenu
        //width: 209
        // Inside this window, which is above everything
        popupType: Popup.Item

        GMenuItem {
            text: "New Folder"
            active: false
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Paste"
            active: false
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Select All"
            active: false
        }
        GMenuSeparator{}
        GMenu {
            id: frontendSubmenu
            title: "Change Frontend"
            //height: 100

            enabled: frontendsInstantiator.count > 0

            Instantiator {
                id: frontendsInstantiator
                model: frontendManager
                delegate: GMenuItem {
                    text: model.frontendName
                    active: !model.frontendActive
                    onTriggered: {
                        console.log("1-- onTrigger() new frontend = " + model.frontendId)

                        // Check if this is the first switch – if so, show dialog
                        if (!settings.dontShowAgain) {
                            warningDialog.pendingFrontendId = model.frontendId
                            warningDialog.open()
                        } else {
                            // If already seen, switch immediately
                            frontendManager.activeFrontend = model.frontendId
                        }
                    }
                }

                onObjectAdded: (index, object) => frontendSubmenu.insertItem(index, object)
                onObjectRemoved: (index, object) => frontendSubmenu.removeItem(object)
            }
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Arrange Icons"
            active: false
        }
        GMenuItem {
            text: "Arrange By..."
            active: false
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Show Desktop in Files"
            active: false
        }
        GMenuItem {
            text: "Open In Terminal"
            active: false
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Change Background..."
            active: false
        }
        GMenuSeparator{}
        GMenuItem {
            text: "Desktop Icons Settings"
            active: false
        }
        GMenuItem { text: "Display Settings"
            active: false
        }
    }
}
