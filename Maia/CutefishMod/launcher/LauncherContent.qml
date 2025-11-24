import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import Maia.Client

import ".."
import "../items"
import "../launcher"
import "../FishUI" as FishUI


Item {
        id: root

        property int iconSize: root.height < 960 ? 96 : 128

        signal hideRequest()

    WallpaperContent{
        id: wallpaperImage
        anchors.fill: parent
        opacity: 0.5
    }

    FastBlur {
        id: wallpaperBlur
        anchors.fill: parent
        radius: 72
        source: wallpaperImage
        cached: false
        visible: wallpaperImage.visible
    }

     LauncherModel {
         id: launcherModel
     }


    ColumnLayout{
        id: mainLayout
        anchors.fill: parent
        anchors.topMargin: 28
        anchors.leftMargin: 0 //launcher.leftMargin
        anchors.rightMargin: 0 //launcher.rightMargin
        anchors.bottomMargin: 86 + 28 //launcher.bottomMargin + 28
        spacing: 0




        Item {
            id: searchItem
            Layout.fillWidth: true
            //height: fontMetrics.height + FishUI.Units.largeSpacing
            Layout.preferredHeight: fontMetrics.height + FishUI.Units.largeSpacing + 3

            // Timer {
            //     interval: 2500; running: true; repeat: true
            //     onTriggered: {
            //         console.log("WWWWWWWWWWWWWWWWwidth = " + searchItem.width)
            //         console.log("HHHHHHHHHHHHHHHHeigth = " + searchItem.height)
            //         console.log("fontMetrics.height = " + fontMetrics.height)
            //         console.log("FishUI.Units.largeSpacing = " + FishUI.Units.largeSpacing)
            //     }
            // }

            TextMetrics {
                id: fontMetrics
                text: _placeLabel.text
            }

            TextField {
                id: textField
                anchors.centerIn: parent
                width: searchItem.width * 0.2
                height: parent.height

                leftPadding: textField.activeFocus ? _placeImage.width + FishUI.Units.largeSpacing : FishUI.Units.largeSpacing
                rightPadding: FishUI.Units.largeSpacing

                selectByMouse: true

                //placeholderText: qsTr("Search")
                wrapMode: Text.NoWrap

                color: "white"

                Item {
                    id: placeHolderItem
                    height: textField.height
                    width: _placeHolderLayout.implicitWidth
                    opacity: 0.6
                    x: textField.activeFocus ? FishUI.Units.smallSpacing : (textField.width - placeHolderItem.width) / 2
                    y: 0

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                     RowLayout {
                         id: _placeHolderLayout
                         anchors.fill: parent

                         Image {
                             id: _placeImage
                             height: placeHolderItem.height - FishUI.Units.largeSpacing
                             width: height
                             sourceSize: Qt.size(width, height)
                             source: Qt.resolvedUrl("../assets/images/system-search-symbolic.svg")
                         }

                        Label {
                            id: _placeLabel
                            color: "white"
                            text: qsTr("Search")
                            visible: !textField.length && !textField.preeditText && (!textField.activeFocus || textField.horizontalAlignment !== Qt.AlignHCenter)
                        }
                    }
                }



                background: Rectangle {
                    opacity: 0.2
                    radius: textField.height * 0.2
                    color: "white"
                    border.width: 0
                }

                Timer {
                    id: searchTimer
                    interval: 500
                    repeat: false
                    onTriggered:{
                        console.log("TTTTTTTTTTTTTTTTTTTTTTTTTIMER searchTimer")
                        launcherModel.search(textField.text)
                    }
                }

                onTextChanged: {
                    if (textField.text === "") {
                        // Switch directly to normal mode
                        launcherModel.search("")
                    } else {
                        searchTimer.start()
                    }
                }

                Keys.onEscapePressed: root.hideRequest()
            }


        }





        Item {
            //height: 14
            Layout.preferredHeight: 14
            Layout.fillWidth: true

            // Rectangle{
            //     anchors.fill: parent
            //     color: "transparent"
            //     border.width: 1
            //     border.color: "orange"
            // }
        }

        Item {
            id: gridItem
            Layout.fillHeight: true
            Layout.fillWidth: true

            Keys.enabled: true
            Keys.forwardTo: appView

            AllAppsView {
                id: appView
                anchors.fill: parent
                anchors.leftMargin: gridItem.width * 0.1
                anchors.rightMargin: gridItem.width * 0.1
                Layout.alignment: Qt.AlignHCenter

                iconSize: root.iconSize + FishUI.Units.largeSpacing * 2

                searchMode: textField.text
                focus: true

                Keys.enabled: true

                onClicked : {
                    console.log("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
                    root.hideRequest()
                }
            }



            // Rectangle{
            //     anchors.fill: gridItem
            //     color: "transparent"
            //     border.width: 1
            //     border.color: "yellow"
            // }

            // Rectangle{
            //     anchors.fill: appView
            //     color: "transparent"
            //     border.width: 1
            //     border.color: "green"
            // }
        }

        PageIndicator {
            id: pageIndicator
            count: appView.count
            currentIndex: appView.currentIndex
            onCurrentIndexChanged: appView.currentIndex = currentIndex
            interactive: true
            spacing: FishUI.Units.largeSpacing
            Layout.alignment: Qt.AlignHCenter
            visible: appView.count > 1

            delegate: Rectangle {
                width: 10
                height: width
                radius: width / 2
                color: index === pageIndicator.currentIndex ? "white" : Qt.darker("white", 1.8)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1

        onClicked: {
            console.log("HHHHHHHHHHHHHHHHHHH ide launcher.hideWindow()")
            root.hideRequest()
        }
    }

    Timer {
        id: clearSearchTimer
        interval: 100
        onTriggered:{
            console.log("TTTTTTTTTTTTTTTTTTTTTTTTTIMER clearSearchTimer")
            textField.text = ""
        }
    }


    Connections {
        target: launcherWindow

        function onVisibleChanged(visible) {
            console.log("QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ")
            if (visible) {
                textField.focus = false
                appView.focus = true
                appView.forceActiveFocus()
            } else {
                clearSearchTimer.restart()
            }
        }
    }



    // Rectangle{
    //     anchors.fill: mainLayout
    //     color: "transparent"
    //     border.width: 1
    //     border.color: "red"
    // }


}



















































