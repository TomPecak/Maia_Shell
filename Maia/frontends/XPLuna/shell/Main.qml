import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick.Effects
import QtCore

import Maia.Backend

import XPLunaFrontend
import "desktop"
import "session"
import "startmenu"
import "taskbar"
import "volume"



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
        backend.installAuroraeTheme(Qt.resolvedUrl("../assets/kwin_themes/XBoomer"))

        backend.installIconTheme(Qt.resolvedUrl("../assets/icons/oxygen"))
        backend.installIconTheme(Qt.resolvedUrl("../assets/icons/hicolor"))

        backend.setAuroraeTheme("XBoomer")
        //backend.setDefaultWindowDecoration()

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

    Timer {
        interval:  128 * 5 //Wait 3 seconds to ensure KWin has started, initialize KWin effects.
        //8ms - FAIL
        //16ms - FAIL
        //32ms - FAIL
        //64ms - FAIL
        //128ms - OK
        //256ms - OK
        //512ms - OK
        running: false
        repeat: false
        onTriggered: {
            //MWindowManagerX11.reconfigure()

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
    }

    WallpaperContent {
        id: wallpaper
        anchors.fill: parent

        onLeftMouseButtonClicked:{
            if(systemVolumeSlider.visible)
                systemVolumeSlider.visible = false
            if(appMenu.visible)
                appMenu.visible = false
            console.log("Wallpapre Left clicked 2")
        }

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
        x: root.x + (root.width - width) / 2
        y: root.y + (root.height - height) / 2
    }

    LogoutDialog {
        id: logOffDialog
        x: root.x + (root.width - width) / 2
        y: root.y + (root.height - height) / 2
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
        x: panel.x
        y: panel.y-height

        width: 380
        height: 478

        visible: false

        onLogoutClicked: {
            logOffDialog.visibility = Window.FullScreen
        }
        onTurnoffClicked: {
            turnOffDialog.visibility = Window.FullScreen
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

    TaskbarContent{
        id: panel
        anchors.bottom: parent.bottom
        //anchors.bottomMargin: 100
        anchors.right: parent.right
        anchors.left: parent.left

        onStartPressed: {
            appMenu.visible = !appMenu.visible
        }

        onEndPressed: {

        }

        property size dimensions: Qt.size(width, height)
        onDimensionsChanged: {
            backend.reservePanelBottomArea(root, panel.x, panel.y, panel.width, panel.height)
        }
    }

    //SystemVolumePopup{
    SystemVolumeWindow{
        id: systemVolumeSlider
        x: panel.x + panel.width - width - 20
        y: panel.y-height

        visible: false

    }


    StickyNotes {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 80
        anchors.rightMargin: 80
    }

    LicenseWarning{
        anchors.centerIn: wallpaper
    }

    BrandingLabel {
        anchors.bottom: panel.top
        anchors.right: panel.right
        anchors.bottomMargin: 18
        anchors.rightMargin: 20
    }

}



