import QtQuick
import QtQuick.Controls

import Maia.Client

Menu {
    id: contextMenu
    //width: 209
    popupType: Popup.Window

    MFrontendModel{
        id: frontendManager
    }

    MenuItem {
        text: "New Folder"
        enabled: false
    }
    MenuSeparator{}
    MenuItem {
        text: "Paste"
        enabled: false
    }
    MenuSeparator{}
    MenuItem {
        text: "Select All"
        enabled: false
    }
    MenuSeparator{}
    Menu {
        id: frontendSubmenu
        title: "Change Frontend"
        //height: 100

        enabled: frontendsInstantiator.count > 0

        Instantiator {
            id: frontendsInstantiator
            model: frontendManager
            delegate: MenuItem {
                text: model.frontendName
                enabled: !model.frontendActive
                onTriggered: {
                    console.log("1-- onTrigger() new frontend = " + model.frontendId)

                    frontendManager.activeFrontend = model.frontendId

                }
            }

            onObjectAdded: (index, object) => frontendSubmenu.insertItem(index, object)
            onObjectRemoved: (index, object) => frontendSubmenu.removeItem(object)
        }
    }
    MenuSeparator{}
    MenuItem {
        text: "Arrange Icons"
        enabled: false
    }
    MenuItem {
        text: "Arrange By..."
        enabled: false
    }
    MenuSeparator{}
    MenuItem {
        text: "Show Desktop in Files"
        enabled: false
    }
    MenuItem {
        text: "Open In Terminal"
        enabled: false
    }
    MenuSeparator{}
    MenuItem {
        text: "Change Background..."
        enabled: false
    }
    MenuSeparator{}
    MenuItem {
        text: "Desktop Icons Settings"
        enabled: false
    }
    MenuItem { text: "Display Settings"
        enabled: false
    }
}
