import QtQml

// How far a banner moves from the top middle of the screen to keep clear of the dock: below a dock
// at the top, to the middle of what is left beside a dock at the side. A dock at the bottom changes
// nothing. Only numbers: BannerWindow.qml moves the banner.
QtObject {
    // Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge or Qt.RightEdge
    property int dockEdge: Qt.TopEdge
    // The strip the dock reserves along its edge
    property real dockStrip: 0
    // On this screen and not under a fullscreen window
    property bool dockVisible: true
    // The most the window has room for sideways
    property real maximumShift: 60

    readonly property real strip: dockVisible ? dockStrip : 0
    readonly property real offsetY: dockEdge === Qt.TopEdge ? strip : 0
    readonly property real offsetX: dockEdge === Qt.LeftEdge ? Math.min(strip / 2, maximumShift)
                                  : dockEdge === Qt.RightEdge ? -Math.min(strip / 2, maximumShift)
                                  : 0
}
