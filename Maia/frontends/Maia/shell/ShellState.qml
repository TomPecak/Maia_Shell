pragma Singleton

import Maia.CrossProcessState

// What the layers of the shell (each its own process) have to know about each other. A change in
// one layer reaches the others at once (Maia/modules/crossprocessstate/README.md).
CrossProcessState {
    category: "MaiaShell"

    // The notification center is open: no banners meanwhile, what comes is seen there
    property bool notificationCenterOpen: false

    // Where the dock rests, or is snapping to after a release (Qt.TopEdge...), the strip it reserves
    // along that edge and its screen: what the layers above it keep clear of
    property int dockEdge: Qt.TopEdge
    property int dockStrip: 0
    property string dockScreen: ""

    // The light or dark mode was changed in one layer (Theme.setDark): the others follow
    signal darkModeSet(bool dark)
}
