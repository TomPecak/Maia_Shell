import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick.Effects
import QtCore
import org.kde.layershell 1.0 as LayerShell

import Maia.Appearance
import Maia.Backend

import XPLunaFrontend
import "desktop"
import "session"
import "startmenu"
import "taskbar"
import "volume"



// XPLuna's shell on Wayland: this window is the desktop (wallpaper, notes, branding) in the
// background layer of the compositor, under all windows. The taskbar, the start menu, the volume
// slider and the session dialogs are layer-shell surfaces of their own (taskbar/, startmenu/,
// volume/, session/), in the layers that keep them where they belong:
//
//   overlay     turn off / log off dialogs (above everything, keyboard to themselves)
//   top         taskbar (reserves its height), start menu, volume slider (above the taskbar)
//   windows     applications (maximized ones end at the taskbar)
//   background  this desktop
Window {
    id: root
    title: qsTr("Maia Wallpaper")
    objectName: "wind1"  //allow to find window on C++ side: QQuickWindow *window = engine.rootObjects().first()->findChild<QQuickWindow*>("wind1");

    visible: true

    width: Screen.width
    height: Screen.height
    color: "black"
    flags: Qt.FramelessWindowHint

    LayerShell.Window.scope: "xpluna-desktop"
    LayerShell.Window.layer: LayerShell.Window.LayerBackground
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // The whole screen, under the taskbar too
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // XPLuna's window decoration the first time; afterwards what the user chose for XPLuna
    FrontendLook {
        frontend: "XPLuna"
        windowDecoration: "aurorae-svg:XBoomer"
    }

    Component.onCompleted: {
        backend.installIconTheme(Qt.resolvedUrl("../assets/icons/oxygen"))
        backend.installIconTheme(Qt.resolvedUrl("../assets/icons/hicolor"))


        // Windows XP did not animate windows: KWin's effects are unloaded (through KWin's D-Bus,
        // also on Wayland). Layer-shell surfaces are in no task list, so nothing has to be hidden
        // from the taskbar or the switcher any more.
        MWindowManagerX11.unloadEffect("kwin4_effect_fadingpopups")
        MWindowManagerX11.unloadEffect("kwin4_effect_scale")
        MWindowManagerX11.unloadEffect("fadingpopups")
        MWindowManagerX11.unloadEffect("scale")
        MWindowManagerX11.unloadEffect("cutefish_squash")
        MWindowManagerX11.unloadEffect("cutefish_scale")
        MWindowManagerX11.unloadEffect("cutefish_popups")
    }


    //----------------------------------------


    //readonly property Vol.SinkModel.

    //property var sink:

    //----------------------------------------

    FontLoader {
        id: tahomaRegular
        source: "../assets/fonts/tahoma.ttf"
    }

    FontLoader {
        id: tahomaBold
        source: "../assets/fonts/tahomabd.ttf"
    }

    FontLoader {
        id: neverMindHandwriting
        source: "../assets/fonts/NeverMindHandwriting-Regular.ttf"
    }

    FontLoader {
        id: neverMindHandwritingMedium
        source: "../assets/fonts/NeverMindHandwriting-Medium.ttf"
    }

    WallpaperContent {
        id: wallpaper
        anchors.fill: parent

        onLeftMouseButtonClicked:{
            if(systemVolumeSlider.visible)
                systemVolumeSlider.visible = false
            if(appMenu.visible)
                appMenu.visible = false
        }
        onRightMouseButtonClicked: (x, y) => desktopMenu.openAt(x, y)

    }

    DesktopMenuWindow {
        id: desktopMenu
    }



    // WebEngineView {
    //     id: youtubeView
    //     width: 450
    //     height: 600
    //     anchors.top: parent.top
    //     anchors.right: parent.right
    //     anchors.margins: 20
    //     url: "https://www.youtube.com/watch?v=izaO5-_nyp0&list=RDGMEMQ1dJ7wXfLlqCjwV0xfSNbA&index=2"  // Youtube link
    // }


    // View3D {
    //     id: view
    //     width: 600
    //     height: 600
    //     anchors.top: parent.top
    //     anchors.right: parent.right
    //     focusPolicy: Qt.NoFocus


    //     PerspectiveCamera {
    //         position: Qt.vector3d(0, 200, 300)
    //         eulerRotation.x: -30
    //     }

    //     DirectionalLight {
    //         eulerRotation.x: -30
    //     }

    // Model {
    //     id: cube
    //     source: "#Cube"
    //     // materials: DefaultMaterial {
    //     //     diffuseColor: Qt.rgba(1, 0, 0, 1) // Set color to black
    //     // }
    //     materials: DefaultMaterial {
    //         diffuseMap: Texture {
    //             //sourceItem: dateTimeDisplay
    //             //sourceItem: wallpaper
    //             source: "qt_logo.png"
    //         }
    //     }
    //     eulerRotation.y: 90

    //     Vector3dAnimation on eulerRotation {
    //         loops: Animation.Infinite
    //         duration: 5000
    //         from: Qt.vector3d(0, 0, 0)
    //         to: Qt.vector3d(360, 0, 360)
    //     }
    // }


    TurnOffDialog {
        id: turnOffDialog
    }

    LogoutDialog {
        id: logOffDialog
    }








    // Column{
    //     anchors.top: parent.top
    //     anchors.horizontalCenter: parent.horizontalCenter
    //     visible: true
    //     Row{
    //         TextField{
    //             placeholderText: appsListEffect.shadowBlur
    //         }
    //         Button{
    //             text: "shadowBlur : real"
    //             onClicked: {
    //                 //appsListEffect.shadowBlur = text
    //             }
    //         }
    //     }
    //     Row{
    //         TextField{

    //         }
    //         Button{
    //             text: "shadowHorizontalOffset : real"
    //         }
    //     }
    //     Row{
    //         TextField{

    //         }
    //         Button{
    //             text: "shadowOpacity : real"
    //         }
    //     }
    //     Row{
    //         TextField{

    //         }
    //         Button{
    //             text: "shadowScale : real"
    //         }
    //     }
    //     Row{
    //         TextField{

    //         }
    //         Button{
    //             text: "shadowVerticalOffset : real"
    //         }
    //     }
    // }




    //AppMenuPopup{
    AppMenuWindow{
        id: appMenu

        onLogoutClicked: {
            logOffDialog.visible = true
        }
        onTurnoffClicked: {
            turnOffDialog.visible = true
        }
    }



    // MProxyWindow{
    //     id: clock3D
    //     source: "qrc:///windows/Clock3DWindow.qml"
    //     //sourceStr: "qrc:///windows/Clock3DWindow.qml"
    //     //source: "qrc:///Clock3D.qml"
    //     //source: "qrc:///MainTest.qml"
    //     proxyVisible: true
    //     anchors.bottom: panel.top
    //     anchors.right: panel.right
    //     width: 200
    //     height: 200
    //     swapInterval: 1
    // }

    // Clock3DContent{
    //     anchors.left: wallpaper.left
    //     anchors.top: wallpaper.top
    //     width: 200
    //     height: 200
    // }

    TaskbarWindow{
        id: panel

        startMenuOpen: appMenu.visible

        onStartPressed: {
            appMenu.visible = !appMenu.visible
        }
        onVolumeClicked: {
            systemVolumeSlider.visible = !systemVolumeSlider.visible
        }
    }

    SystemVolumeWindow{
        id: systemVolumeSlider
    }


    StickyNotes {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 80
        anchors.rightMargin: 80
    }

    // Above the taskbar (the desktop reaches under it)
    BrandingLabel {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: panel.height + 18
        anchors.rightMargin: 20
    }

}



