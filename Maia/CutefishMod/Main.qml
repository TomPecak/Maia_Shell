import QtQuick

import "./menu"
import "./contents"
import "./windows"


Window{
	id: root

	visible: true

	width: Screen.width
	height: Screen.height
	flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint //| Qt.X11BypassWindowManagerHint
	visibility: Window.FullScreen

	color: "yellow"

	ChangeFrontendMenu{
		id: constextMenu
	}

	MouseArea{
		anchors.fill: parent
		MouseArea {
			anchors.fill: parent
			acceptedButtons: Qt.LeftButton | Qt.RightButton
			onClicked: (mouse)=> {
			if (mouse.button === Qt.RightButton)
				constextMenu.popup()
			}
		}
	}

	WallpaperContent{
		id: wallpaper
		anchors.fill: parent
	}

	DockWindow{
		x: root.width/2 - width/2
		y: root.height - height - 6
		visible: true
	}

	// DockContent{
	// 	anchors.bottom: parent.bottom
	// 	anchors.horizontalCenter: parent.horizontalCenter
	// 	anchors.bottomMargin: 6
	// }

}
