import QtCore
import QtQuick
import QtQuick.Controls
import org.kde.layershell 1.0 as LayerShell

import Maia.Appearance
import Maia.Backend

import GnomeFrontend
import "controlboard"
import "desktop"
import "dock"
import "launcher"
import "toppanel"

// The Ubuntu 24.04 shell on Wayland: this window is the desktop (wallpaper) in the background
// layer of the compositor, under all windows. The panels and popups are layer-shell surfaces of
// their own, in the layers that keep them where they belong:
//
//   overlay     desktop menu and its dialog (desktop/)
//   top         top bar (reserves 29 px), dock (reserves 66 px), control board, app grid
//   windows     applications (maximized ones fill what the bars leave)
//   background  this desktop
Window {
    id: root
    title: qsTr("Maia")
    visible: true

    width: Screen.width
    height: Screen.height
    color: "black"
    flags: Qt.FramelessWindowHint

    LayerShell.Window.scope: "ubuntu-desktop"
    LayerShell.Window.layer: LayerShell.Window.LayerBackground
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    // The whole screen, under the bars too
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    // Breeze the first time (as GNOME's look is closest to it); afterwards the user's choice
    FrontendLook {
        frontend: "Ubuntu 24.04"
        windowDecoration: "kdecoration:org.kde.breeze"
    }

    FontLoader {
        id: ubuntuSans
        source: "../assets/fonts/UbuntuSans.ttf"
    }

    FontLoader{
        id: neverMindHandwritingMedium
        source: "../assets/fonts/NeverMindHandwriting-Medium.ttf"
    }

    DesktopMenuWindow {
        id: desktopMenu
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: "../assets/images/warty-final-ubuntu.png"

        MouseArea {
            // anchors.top: topPanel.bottom
            // anchors.left: sidePanel.right
            // anchors.bottom: parent.bottom
            // anchors.right: parent.right

            anchors.fill: parent

            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                           if(controlBoard.visible){
                               controlBoard.visible = false
                           }

                           if (mouse.button === Qt.RightButton){
                               desktopMenu.openAt(mouse.x, mouse.y)
                               //recentAppsContextMenu.popup()
                           }
                       }
            // onPressAndHold: (mouse) => {
            //     if (mouse.source === Qt.MouseEventNotSynthesized)
            //         contextMenu.popup()
            // }
        }
    }


    ControlBoardWindow{
        id: controlBoard
    }

    TopPanelWindow{
        id: topPanel

        controlBoardVisible: controlBoard.visible

        onClicked: {
            controlBoard.visible = !controlBoard.visible
        }
    }

    SidePanelWindow{
        id: sidePanel

        onLauncherButtonClicked: {
            appLauncherWindow.visible = !appLauncherWindow.visible
        }
    }

    AppsLauncherWindow{
        id: appLauncherWindow
    }

    // RemoteWindow{
    //     source: "../AppsLauncherWindow.qml"
    //     anchors.fill: parent
    //     width: 300
    //     height: 300
    //     visible: true
    // }


    // TopPanelContent{
    //     id: topPanel
    //     x:0
    //     y:0
    //     width: root.width
    //     height: 29
    //     visible: true
    // }

    // ControlBoard{
    //     id: controlBoard
    //     x: Screen.width - width - 6
    //     y: topPanel.height + 6
    //     visible: false
    //     //flags: Qt.FramelessWindowHint
    //     Component.onCompleted: {
    //     }
    // }

    // SidePanelContent{
    //     id: sidePanel
    //     x:0
    //     y: 29
    //     width: 66
    //     height: root.height - sidePanel.y
    //     visible: true

    //     property size dimensions: Qt.size(width, height)
    //     onDimensionsChanged: {
    //     }

    //     onLauncherButtonClicked: {
    //         appLauncherWindow.visible = ! appLauncherWindow.visible
    //     }
    // }


    // Column{
    //     anchors.right: parent.right
    //     anchors.bottom: parent.bottom
    // Button{
    //     text: "poweroff"
    //     onClicked: {
    //         Session.powerOff()
    //     }
    // }
    // Button{
    //     text: "logout"
    //     onClicked: {
    //         Session.logout()
    //     }
    // }
    // Button{
    //     text: "reboot"
    //     onClicked: {
    //         Session.reboot()
    //     }
    // }
    // Button{
    //     text: "Luna XP"
    //     onClicked: {
    //         frontendManager.activeFrontend = "351c97c34271d2a3ac6c180b951c920528de19d8"
    //     }
    // }
    //    }

    // AppLauncherContent{
    //     id: appLauncherWindow
    //     x: sidePanel.width
    //     y: topPanel.height
    //     width: root.width - sidePanel.width
    //     height: root.height - topPanel.height
    //     visible: false
    // }


    Text {
        id: maiaText
        text: "Maia Shell"
        font.family: "NeverMind Handwriting"
        font.pointSize: 24
        color: "#FFFFFF"
        opacity: 0  // Start with fully transparent
        anchors.bottom: wallpaper.bottom
        anchors.bottomMargin: 18
        anchors.rightMargin: 20
        anchors.right: wallpaper.right

        // Timer to trigger the animation after 5 seconds
        Timer {
            id: fadeInTimer
            interval: 3000  // 5 seconds delay
            running: true
            repeat: false
            onTriggered: {
                fadeInAnimation.start()
            }
        }

        // Animation to fade in the text
        NumberAnimation {
            id: fadeInAnimation
            target: maiaText
            property: "opacity"
            from: 0
            to: 0.7  // Target opacity
            duration: 1000  // Duration of the fade-in effect (1 second)
            easing.type: Easing.InOutQuad  // Smooth easing curve
        }
    }

}
