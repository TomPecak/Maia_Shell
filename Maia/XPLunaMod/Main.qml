import QtQuick
import QtQuick.Controls

import Maia.Client

Window {
    id: root
    title: qsTr("Maia Wallpaper")
    objectName: "wind1"  //allow to find window on C++ side: QQuickWindow *window = engine.rootObjects().first()->findChild<QQuickWindow*>("wind1");

    visible: true

    width: Screen.width
    height: Screen.height
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint //| Qt.X11BypassWindowManagerHint
    visibility: Window.FullScreen

    Component.onCompleted: {
        //backend.installAuroraeTheme("qrc:/assets/kwin_themes/XBoomer")

        //backend.installIconTheme("qrc:/assets/icons/oxygen")
        //backend.installIconTheme("qrc:/assets/icons/hicolor")

        //backend.setAuroraeTheme("XBoomer")


        //unload unesesery kwin effects
        MWindowManagerX11.unloadEffect("kwin4_effect_fadingpopups")
        MWindowManagerX11.unloadEffect("kwin4_effect_scale")
        MWindowManagerX11.unloadEffect("fadingpopups")
        MWindowManagerX11.unloadEffect("scale")
        MWindowManagerX11.unloadEffect("cutefish_squash")
        MWindowManagerX11.unloadEffect("cutefish_scale")
        MWindowManagerX11.unloadEffect("cutefish_popups")


        MWindowManagerX11.hideFromTaskbar(root, true);
        MWindowManagerX11.hideFromSwitcher(root, true);
        MWindowManagerX11.hideFromPager(root, true);

        backend.setX11WindowTypeAsDesktop(root)
    }


    //----------------------------------------


    //readonly property Vol.SinkModel.

    //property var sink:

    //----------------------------------------

    FontLoader {
        id: tahomaRegular
        source: "qrc:/assets/fonts/tahoma.ttf"
    }

    FontLoader {
        id: tahomaBold
        source: "qrc:/assets/fonts/tahomabd.ttf"
    }

    FontLoader {
        id: neverMindHandwriting
        source: "qrc:/assets/fonts/NeverMindHandwriting-Regular.ttf"
    }

    FontLoader {
        id: neverMindHandwritingMedium
        source: "qrc:/assets/fonts/NeverMindHandwriting-Medium.ttf"
    }

    Timer {
        interval:  120*1000 //128 * 5 //Wait 3 seconds to ensure KWin has started, initialize KWin effects.
        //8ms - FAIL
        //16ms - FAIL
        //32ms - FAIL
        //64ms - FAIL
        //128ms - OK
        //256ms - OK
        //512ms - OK
        running: true
        repeat: false
        // onTriggered: {
        //     ////MWindowManagerX11.reconfigure()

        //     // MWindowManagerX11.unloadEffect("kwin4_effect_fadingpopups")
        //     // MWindowManagerX11.unloadEffect("kwin4_effect_scale")
        //     // MWindowManagerX11.unloadEffect("fadingpopups")
        //     // MWindowManagerX11.unloadEffect("scale")
        //     // MWindowManagerX11.unloadEffect("cutefish_squash")
        //     // MWindowManagerX11.unloadEffect("cutefish_scale")
        //     // MWindowManagerX11.unloadEffect("cutefish_popups")

        //     // MWindowManagerX11.hideFromTaskbar(root, true);
        //     // MWindowManagerX11.hideFromSwitcher(root, true);
        //     // MWindowManagerX11.hideFromPager(root, true);

        //     // backend.setX11WindowTypeAsDesktop(root)
        // }
    }


    MFrontendModel{
        id: frontendManager
    }


    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse)=> {
            if (mouse.button === Qt.RightButton)
                contextMenu.popup()
        }
    }

    Menu {
        id: contextMenu
        //width: 209
        popupType: Popup.Window

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
                            // If already seen, switch immediately
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
}
