import QtQuick

import Maia.Backend

import "./menu"
import "./contents"
import "./windows"
import "./launcher"
import "./statusbar"


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

		onAppsItemClicked: {
			appLauncherWindow.visible = !appLauncherWindow.visible
			console.log("MMMMMMMMMMMMMMMMMMain apps icon clicked !!!!!")
		}
	}

	// MProxyWindow{
	// 	id: appLauncherWindow
	// 	source: "./windows/AppsLauncherWindow.qml"
	// 	proxyVisible: true
	// 	anchors.right: parent.right
	// 	anchors.left: parent.left
	// 	anchors.top: parent.top
	// 	anchors.bottom: parent.bottom
	// 	swapInterval: 1
	// }

	AppsLauncherWindow{
		id: appLauncherWindow

		x: root.x
		y: root.y
		width: root.width
		height: root.height
	}

	StatusbarWindow{
		x: 0
		y: 0
		width: root.width
		wallpaperUrl: wallpaper.source //pass wallpaper Url to Statusbar

		visible: !appLauncherWindow.visible
	}

}
