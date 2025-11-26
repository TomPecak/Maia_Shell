import QtCore
import QtQuick
import QtQuick.Controls

import Maia.Backend

import "./contents"
import "./style"
import "./popups"
import "./windows"



/*
import "./hussars"

Window{
    id: root
    title: qsTr("Red Theme")
    visible: true

    width: Screen.width
    height: Screen.height
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    visibility: Window.FullScreen

    FontLoader {
        id: cnnFont
        source: "./fonts/CNN.TTF"
    }

    FontLoader{
        id: neverMindHandwritingMedium
        source: "./fonts/NeverMindHandwriting-Medium.ttf"
    }

        Component.onCompleted: {
            //backend.windowManager.reconfigure();
            backend.setX11WindowTypeAsDesktop(root)
            backend.setDefaultWindowDecoration()

            MWindowManagerX11.hideFromTaskbar(root, true);
            MWindowManagerX11.hideFromSwitcher(root, true);
            MWindowManagerX11.hideFromPager(root, true);
        }

        Image {
            id: wallpaper
            anchors.fill: parent
            //source: "./images/warty-final-ubuntu.png"
            source: "./images/hussars.jpg"
            //source: "./images/3840x2160.svg"
            //source: "./images/white_wallpaper.png"
            //source: "./images/blue_wallpaper.bmp"
            //source: "./images/red_wallpaper.bmp"
            //source: "./images/green_wallpaper.bmp"

            MouseArea {
                // anchors.top: topPanel.bottom
                // anchors.left: sidePanel.right
                // anchors.bottom: parent.bottom
                // anchors.right: parent.right

                anchors.fill: parent

                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                               // if(controlBoard.visible){
                               //     controlBoard.visible = false
                               // }

                               // if (mouse.button === Qt.RightButton){
                               //     contextMenu.popup()
                               //     //recentAppsContextMenu.popup()
                               // }
                           }
                // onPressAndHold: (mouse) => {
                //     if (mouse.source === Qt.MouseEventNotSynthesized)
                //         contextMenu.popup()
                // }
            }
        }

        TaskbarContent{
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.margins: 5

        }

        TopPanelContent{
            id: topPanel

            x:0
            y:0
            width: root.width
            height: 29
            visible: true

            controlBoardVisible: false


            property size dimensions: Qt.size(width, height)
            onDimensionsChanged: {
                backend.reservePanelTopArea(root, topPanel.x, topPanel.y, topPanel.width, topPanel.height)
            }

            onClicked: {

            }
        }

        MProxyWindow{
            id: appLauncherWindow
            source: "./windows/AppsLauncherWindow.qml"
            //source: Qt.resolvedUrl("./windows/AppsLauncherWindow.qml")
            proxyVisible: true
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            swapInterval: 1

            onProxyVisibleChanged: {
                console.log("9999999999999999 PROXY VISIBLE CHANGED !! proxyVisible = " + appLauncherWindow.proxyVisible)
            }
        }

}*/




Window {
    id: root
    title: qsTr("Maia")
    visible: true

    width: Screen.width
    height: Screen.height
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint //| Qt.X11BypassWindowManagerHint
    visibility: Window.FullScreen

    Component.onCompleted: {
        //backend.windowManager.reconfigure();
        backend.setX11WindowTypeAsDesktop(root)
        backend.setDefaultWindowDecoration()

        MWindowManagerX11.hideFromTaskbar(root, true);
        MWindowManagerX11.hideFromSwitcher(root, true);
        MWindowManagerX11.hideFromPager(root, true);
    }

    FontLoader {
        id: ubuntuSans
        source: "./fonts/UbuntuSans.ttf"
    }

    FontLoader{
        id: neverMindHandwritingMedium
        source: "./fonts/NeverMindHandwriting-Medium.ttf"
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
        popupType: Popup.Window

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

    Timer {
        id: initTimer
        interval: 1 //wait for 1000ms to ensure that kwin has started
        running: true
        repeat: false
        onTriggered: {
            // turn off kwin panel effects
            backend.setX11WindowTypeAsDesktop(root);

            MWindowManagerX11.hideFromTaskbar(root, true);
            MWindowManagerX11.hideFromSwitcher(root, true);
            MWindowManagerX11.hideFromPager(root, true);
        }
    }


    Image {
        id: wallpaper
        anchors.fill: parent
        source: "./images/warty-final-ubuntu.png"
        //source: "./images/3840x2160.svg"
        //source: "./images/white_wallpaper.png"
        //source: "./images/blue_wallpaper.bmp"
        //source: "./images/red_wallpaper.bmp"
        //source: "./images/green_wallpaper.bmp"

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
                               contextMenu.popup()
                               //recentAppsContextMenu.popup()
                           }
                       }
            // onPressAndHold: (mouse) => {
            //     if (mouse.source === Qt.MouseEventNotSynthesized)
            //         contextMenu.popup()
            // }
        }
    }


    //ControlBoardPopup{
    ControlBoardWindow{
        id: controlBoard
        x: Screen.width - width - 6
        y: topPanel.height + 6
        visible: false
        //flags: Qt.FramelessWindowHint
    }

    TopPanelContent{
        id: topPanel

        x:0
        y:0
        width: root.width
        height: 29
        visible: true

        controlBoardVisible: controlBoard.visible


        property size dimensions: Qt.size(width, height)
        onDimensionsChanged: {
            backend.reservePanelTopArea(root, topPanel.x, topPanel.y, topPanel.width, topPanel.height)
        }

        onClicked: {
            controlBoard.visible = !controlBoard.visible
        }
    }

    SidePanelContent{
        id: sidePanel
        x:0
        y: 29
        width: 66
        height: root.height - sidePanel.y
        visible: true

        property size dimensions: Qt.size(width, height)
        onDimensionsChanged: {
            backend.reservePanelLeftArea(root, sidePanel.x, sidePanel.y, sidePanel.width, sidePanel.height)
        }

        onLauncherButtonClicked: {
            appLauncherWindow.proxyVisible = ! appLauncherWindow.proxyVisible
        }
    }

    MProxyWindow{
        id: appLauncherWindow
        source: "./windows/AppsLauncherWindow.qml"
        //source: Qt.resolvedUrl("./windows/AppsLauncherWindow.qml")
        proxyVisible: false
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        swapInterval: 1

        onProxyVisibleChanged: {
            console.log("9999999999999999 PROXY VISIBLE CHANGED !! proxyVisible = " + appLauncherWindow.proxyVisible)
        }
    }



    // RemoteWindow{
    //     source: "./AppsLauncherWindow.qml"
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
    //         //backend.setX11WindowTypeAsDock(controlBoard);
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
    //         backend.reservePanelLeftArea(root, sidePanel.x, sidePanel.y, sidePanel.width, sidePanel.height)
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
    //         MSessionManager.poweroff()
    //     }
    // }
    // Button{
    //     text: "logout"
    //     onClicked: {
    //         MSessionManager.logout()
    //     }
    // }
    // Button{
    //     text: "reboot"
    //     onClicked: {
    //         MSessionManager.reboot()
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
