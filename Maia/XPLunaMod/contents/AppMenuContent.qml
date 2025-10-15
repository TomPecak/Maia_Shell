import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Maia.Client
import "../style_items"

Image{
    id: root

    width: 380
    height: 478
    source: "../assets/images/start_menu/start_menu.png"

    signal hideRequest()
    signal logoutClicked()
    signal turnoffClicked()

    function requestHide(){
        hideRequest()
        resetState()
    }

    function resetState(){
        appsListMenu.hide()
    }

    onVisibleChanged: {
        if(!visible){
            resetState()
        }
    }

    MFavoritesAppsModel{
    id: favoriteAppsModel
    }

    FontLoader {
        id: tahomaRegular
        source: "../assets/fonts/tahoma.ttf"
    }

    FontLoader {
        id: tahomaBold
        source: "../assets/fonts/tahomabd.ttf"
    }

    Rectangle{
        id: lastUsedSection
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 81
        width: 176
        height: 236
        color: "#FFFFFF"
        clip: true

        Column {
            anchors.fill: parent
            spacing: 4

            Repeater {
                model: favoriteAppsModel

                delegate: Rectangle {
                    id: recentAppsDelegate
                    width: parent.width
                    height: 36

                    required property string appName
                    required property string appIcon
                    required property string appExec
                    required property string appId

                    color: recentAppsDelegateMouseArea.containsMouse ? "#316ac5" : "#FFFFFF"

                    Image {
                        id: recentAppsImage
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://backend_app_icon/" + recentAppsDelegate.appIcon
                        width: 32
                        height: 32
                        fillMode: Image.PreserveAspectFit
                        Component.onCompleted: {
                            //console.log("WARING TODO: fix model and icon source, icon should return full path to icon in icon provider")
                        }
                    }

                    Text {
                        anchors.left: recentAppsImage.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - recentAppsImage.width - anchors.leftMargin - 8 // Odjęcie marginesów
                        text: recentAppsDelegate.appName

                        font.family: "Tahoma"
                        font.styleName: "Regular"
                        font.pointSize: 8.0
                        font.kerning: true
                        font.hintingPreference: Font.PreferFullHinting
                        renderType: Text.NativeRendering
                        antialiasing: false

                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        color: recentAppsDelegateMouseArea.containsMouse ? "#FFFFFF" : "#373738"
                    }

                    MouseArea {
                        id: recentAppsDelegateMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: (mouse)=> {
                                       if (mouse.button == Qt.RightButton) {
                                           console.log("Try popup contex menu " + mouse.x)
                                           recentAppsContextMenu.focus = true
                                           recentAppsContextMenu.popup(mouse.x + 1, mouse.y)
                                       } else {
                                           root.requestHide()
                                           console.log("qml: try run app: id = " + appId + " exec = " + appExec);
                                           backend.runCommand(appExec)
                                       }
                                   }
                    }

                    XPMenu {
                        id: recentAppsContextMenu
                        z: 1
                        width: 149
                        height: 178

                        XPMenuItem {
                            text: "Open"
                            fontWeight: Font.Bold
                            onTriggered: {
                                recentAppsContextMenu.close()
                                root.requestHide()
                                backend.runCommand(exec)
                            }
                        }
                        XPMenuItem {
                            text: "Run as..."
                            active: false
                        }
                        XPMenuItem {
                            text: "Pin to Start menu"
                            active: false
                        }
                        XPMenuSeparator{
                        }
                        XPMenuItem {
                            text: "Send to"
                            active: false
                        }
                        XPMenuSeparator{
                        }
                        XPMenuItem {
                            text: "Copy"
                            active: false
                        }
                        XPMenuSeparator{
                        }
                        XPMenuItem {
                            text: "Remove from This List"
                            onTriggered: {
                                favoriteAppsModel.removeFavorite(appId);
                            }
                        }
                        XPMenuItem {
                            text: "Rename"
                            active: false
                        }
                        XPMenuSeparator{
                        }
                        XPMenuItem {
                            text: "Properties"
                            active: false
                        }
                    }

                }
            }
        }
    }

    Image{
        id: allProgramsButton
        x: 8
        y: 408
        height: 24
        width: 174

        property bool activeHover: allProgramsButtonMouseArea.containsMouse? (true) : (appsListMenu.visible ? true : false)
        source: activeHover? "../assets/images/start_menu/all_programs_button_hover.png" : "../assets/images/start_menu/all_programs_button_normal.png"

        Text{
            id: allProgramsText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 38
            text: "All Programs"

            font.family: "Tahoma"
            font.styleName: "Bold"
            font.pointSize: 8.0
            font.kerning: true
            font.hintingPreference: Font.PreferFullHinting
            renderType: Text.NativeRendering
            antialiasing: false

            color: allProgramsButton.activeHover ? "#ffffff" : "#373738"
        }

        Timer {
            id: hoverTimer
            interval: 500
            repeat: false
            onTriggered: {
                if(!appsListMenu.visible){
                    appsListMenu.showWithAnimation()
                }
            }
        }

        MouseArea{
            id: allProgramsButtonMouseArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                hoverTimer.start()
            }
            onClicked: {
                hoverTimer.stop()
                if(!appsListMenu.visible){
                    appsListMenu.showWithAnimation()
                }else{
                    appsListMenu.hideWithAnimation()
                }
            }
            onExited: {
                hoverTimer.stop()
            }
        }

        Rectangle{
            id: appsListMenu
            anchors.left: parent.left
            anchors.leftMargin: 137
            anchors.bottom: parent.bottom
            color: "#ffffff"
            border.color: "#55a1ff"
            border.width: 1
            height: 400
            width: 218
            visible: false //work at layer
            opacity: 0.0 //work at layer

            layer.enabled: true
            layer.effect: MultiEffect{
                id: appsListEffect
                //source: appsListMenu
                //anchors.fill: appsListMenu
                autoPaddingEnabled: true
                shadowEnabled: true
                shadowBlur: shadowBlurSlider.value
                shadowHorizontalOffset: shadowHorizontalOffsetSlider.value
                shadowOpacity: shadowOpacitySlider.value
                shadowScale: shadowScaleSlider.value
                shadowVerticalOffset: shadowVerticalOffsetSlider.value
                visible: true //don't work in layer
                opacity: 1.0 //don't work in layer
            }


            function showWithAnimation(){
                appsListOpacityAnimation.show()
            }
            function hideWithAnimation(){
                appsListOpacityAnimation.hide()
            }
            function hide(){
                appsListMenu.visible = false
                appsListMenu.opacity = 0.0
            }

            NumberAnimation on opacity{
                id: appsListOpacityAnimation
                easing.type: Easing.OutExpo
                alwaysRunToEnd: false

                function show(){
                    appsListMenu.visible = true
                    from = appsListMenu.opacity
                    to = 1.0
                    start();
                }
                function hide(){
                    from = appsListMenu.opacity
                    to = 0.0
                    start();
                }

                duration: 500

                onFinished: {
                    if(appsListMenu.opacity === 0.0)
                        appsListMenu.visible = false
                }
            }


            Image{
                id: appListLeftBorder
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                fillMode: Image.TileVertically
                width: 6
                source: "../assets/images/app_list/app_list_right_border.png"
            }

            ListView {
                id: appsListView
                anchors.top: parent.top
                anchors.bottom: searchSeparator.top
                anchors.bottomMargin: 3
                anchors.left: appListLeftBorder.right
                anchors.right: parent.right
                model: appsListModel
                clip: true
                //cacheBuffer: 2147483647 - The cache with a high value has been disabled, performance issues arise with using the proxy model and application search, and there was an issue with displaying delegates in the grid view layout.

                delegate: Item {
                    id: appsListDelegate
                    width: appsListView.width
                    height: 23

                    required property string name
                    required property string icon
                    required property string exec
                    required property string id

                    Rectangle{
                        anchors.fill: parent
                        visible: delegateMouseArea.containsMouse
                        color: delegateMouseArea.containsMouse ? "#1665CB" : "#FFFFFF"
                    }

                    Image {
                        id: appListIcon
                        source: "image://backend_app_icon/" + appsListDelegate.icon
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.topMargin: 5
                        width: 16
                        height: 16
                    }

                    Text {
                        text: appsListDelegate.name
                        anchors.left: appListIcon.right
                        anchors.leftMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 6

                        font.family: "Tahoma"
                        font.styleName: "Regular"
                        font.pointSize: 8.0
                        font.kerning: true
                        font.hintingPreference: Font.PreferFullHinting
                        renderType: Text.NativeRendering
                        antialiasing: false

                        color: delegateMouseArea.containsMouse ? "#FFFFFF" : "#000000"
                    }



                    MouseArea {
                        id: delegateMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton

                        onClicked: (mouse)=> {
                                       if (mouse.button === Qt.RightButton) {
                                           contextMenu.focus = true
                                           contextMenu.popup(mouse.x + 1, mouse.y)
                                           //contextMenu.open()
                                       } else {
                                           root.requestHide()
                                           backend.runCommand(exec)
                                           searchField.text = ""
                                       }
                                   }

                    }


                    XPMenu {
                        id: contextMenu
                        z: 1
                        width: 127
                        height: 229

                        Component.onCompleted: {
                            //console.log("WARNING: TODO: change first item font to windows xp font");
                            //console.log("WARNING: TODO: add shadow");
                            //console.log("WARNING: TODO: add opacity animation");
                            //console.log("WARNING: TODO: add arrot to 'Send to' menu item");
                        }

                        XPMenuItem {
                            id: openMenuItem
                            text: "Open"
                            fontWeight: Font.Bold
                            onTriggered: {
                                contextMenu.close()
                                root.requestHide()
                                backend.runCommand(exec)
                            }
                        }

                        XPMenuItem {
                            id: runAsMenu
                            text: "Run as..."
                            active: false
                        }

                        XPMenuItem {
                            id: pinToStartMenuItem
                            text: "Pin to Start menu"
                            onTriggered: {
                                favoriteAppsModel.addFavorite(id);
                            }
                        }

                        XPMenuSeparator {
                        }

                        XPMenuItem {
                            id: sendToMenuItem
                            text: qsTr("Send To")
                            active: false
                        }

                        XPMenuSeparator {
                        }

                        XPMenuItem {
                            id: cutMenuItem
                            text: qsTr("Cut")
                            active: false
                        }
                        XPMenuItem {
                            id: copyMenuItem
                            text: qsTr("Copy")
                            active: false
                        }
                        XPMenuSeparator {
                        }
                        XPMenuItem {
                            id: createShortcut
                            text: qsTr("Create Shortcut")
                            active: false
                        }
                        XPMenuItem {
                            id: deleteMenuItem
                            text: qsTr("Delete")
                            active: false
                        }
                        XPMenuItem {
                            id: renameMenuItem
                            text: qsTr("Rename")
                            active: false
                        }
                        XPMenuSeparator {
                        }
                        XPMenuItem {
                            id: sortByNameMenuItem
                            text: qsTr("Sort by Name")
                            active: false
                        }
                        XPMenuItem {
                            id: propertiesMenuItem
                            text: qsTr("Properties")
                            active: false
                        }
                    }
                }
            }

            Image{
                id: searchSeparator

                anchors.left: appListLeftBorder.right
                anchors.bottom: searchField.top
                anchors.bottomMargin: 3
                anchors.right: parent.right
                anchors.rightMargin: 1

                fillMode: Image.TileVertically
                height: 1
                source: "../assets/images/app_list/search_separator.png"
            }

            TextField {
                id: searchField
                placeholderText: "Search"

                font.family: "Tahoma"
                font.styleName: "Regular"
                font.pointSize: 8.0
                font.kerning: true
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                antialiasing: false

                Component.onCompleted: {
                    console.log("WARNING TODO: turn off font antialiasing doesn't work?")
                }

                anchors.right: parent.right
                anchors.rightMargin: 1
                anchors.left: appListLeftBorder.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3

                background: Rectangle{
                    anchors.fill: parent
                    color: "#ffffff"
                    border.color: "#ffffff"
                    border.width: 0
                    radius: 0
                }

                onTextChanged: {
                    appsListModel.setFilterFixedString(searchField.text);
                }
            }
        }
    }


    Rectangle{
        id: turnOffButtonBackground
        x: 248
        y: 442
        width: 130
        height: 30
        color: "#00316ac5"

        Item{
            id:turnOffButtonContent
            x:0
            y:0

            Image{
                id: appMenuTurnOffButton
                x: 3
                y: 3
                width: 24
                height: 24
                source: "../assets/images/power_off_button.png"
            }

            Text{
                id: turnOffComputerTxt
                x: 30
                y: 8

                font.family: "Tahoma"
                font.styleName: "Regular"
                font.pointSize: 8.0
                font.kerning: true
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                antialiasing: false

                text: "Turn Off  Computer"
                color: "white"
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled:  true
            onEntered: {
                turnOffButtonBackground.color = "#ff316ac5"
                appMenuTurnOffButton.source = "../assets/images/power_off_button_hover.png"
            }
            onExited: {
                turnOffButtonBackground.color = "#00316ac5"
                appMenuTurnOffButton.source = "../assets/images/power_off_button.png"
            }
            onPressed: {
                turnOffButtonContent.x = 1;
                turnOffButtonContent.y = 1;
            }
            onReleased: {
                turnOffButtonContent.x = 0;
                turnOffButtonContent.y = 0;
                if (containsMouse) {
                    root.turnoffClicked()
                    root.requestHide()
                }
            }
        }
    }

    Rectangle{
        id: logoutButtonBackground
        x: 173
        y: 442
        width: 75
        height: 30
        color: "#00316ac5"

        Item{
            id: logoutButtonContent
            x:0
            y:0

            Image{
                id:appMenuLogoutButton
                x: 3
                y: 3
                width: 24
                height: 24
                source: "../assets/images/menu_start_logout_normal.png"
            }

            Text{
                id: logoutButtonText
                x: 30
                y: 8

                font.family: "Tahoma"
                font.styleName: "Regular"
                font.pointSize: 8.0
                font.kerning: true
                font.hintingPreference: Font.PreferFullHinting
                renderType: Text.NativeRendering
                antialiasing: false

                text: qsTr("Log Off")
                color: "white"
            }
        }

        MouseArea{
            anchors.fill: parent
            hoverEnabled:  true
            onEntered: {
                logoutButtonBackground.color = "#ff316ac5"
                appMenuLogoutButton.source = "../assets/images/menu_start_logout_hover.png"
            }
            onExited: {
                logoutButtonBackground.color = "#00316ac5"
                appMenuLogoutButton.source = "../assets/images/menu_start_logout_normal.png"
            }
            onPressed: {
                logoutButtonContent.x = 1;
                logoutButtonContent.y = 1;
            }
            onReleased: {
                logoutButtonContent.x = 0;
                logoutButtonContent.y = 0;
                if (containsMouse) {
                    root.logoutClicked();
                    root.requestHide();
                }
            }
        }
    }

    Rectangle{
        id: shadowAdjuster
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        implicitWidth: 120
        implicitHeight: 200
        color: "red"
        visible: false
        enabled: false

        Column{
            Text{
                text: "shadowBlur " + shadowBlurSlider.value.toFixed(1)
            }
            Slider {
                id: shadowBlurSlider
                from: 0.0
                //value: 1.0
                value: 0.4
                to: 1.0
            }
            Text{
                text: "shadowHorizontalOffset " + shadowHorizontalOffsetSlider.value.toFixed(1)
            }
            Slider {
                id: shadowHorizontalOffsetSlider
                from: -10.0
                //value: 0.0
                value: 2.4
                to: 10.0
            }

            Text{
                text: "shadowOpacity " + shadowOpacitySlider.value.toFixed(1)
            }
            Slider {
                id: shadowOpacitySlider
                from: 0.0
                //value: 1.0
                value: 0.5
                to: 1.0
            }


            Text{
                text: "shadowScale " + shadowScaleSlider.value.toFixed(1)
            }
            Slider {
                id: shadowScaleSlider
                from: 0.0
                value: 1.0
                to: 2.0
            }

            Text{
                text: "shadowVerticalOffset " + shadowVerticalOffsetSlider.value.toFixed(1)
            }
            Slider {
                id: shadowVerticalOffsetSlider
                from: -10.0
                //value: 0.0
                value: 2.4
                to: 10.0
            }
        }
    }
}
