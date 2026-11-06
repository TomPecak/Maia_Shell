import QtQuick
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend

import "menu"
import "contents"
import "windows"
import "launcher"
import "statusbar"
import CutefishFrontend


// The desktop: this window shows the wallpaper. On Wayland it is a layer-shell surface in the
// background layer, anchored to all edges of the screen, like the desktops of Lumen and Maia: the
// compositor keeps it below every window, it never shows up as a window (no decoration, no task
// bar entry, no focus) and it covers the whole screen. Its size, position and stacking come from
// the layer surface, not from window flags (WindowStaysOnBottomHint and full screen visibility
// were X11 window manager hints).
Window{
	id: root

	visible: true

	width: Screen.width
	height: Screen.height
	flags: Qt.FramelessWindowHint

	LayerShell.Window.scope: "cutefish-desktop"
	LayerShell.Window.layer: LayerShell.Window.LayerBackground
	LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
							   | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
	// The whole screen, also below panels that reserve an area
	LayerShell.Window.exclusionZone: -1
	LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

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
		visible: true

		onAppsItemClicked: {
			appLauncherWindow.visible = !appLauncherWindow.visible
			console.log("MMMMMMMMMMMMMMMMMMain apps icon clicked !!!!!")
		}
	}

	// MProxyWindow{
	// 	id: appLauncherWindow
	// 	source: "../windows/AppsLauncherWindow.qml"
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
		wallpaperUrl: wallpaper.source //pass wallpaper Url to Statusbar

		visible: !appLauncherWindow.visible
	}

}
