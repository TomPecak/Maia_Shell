import QtQuick

import MaiaFrontend

// Where something at the top of the screen rests (a banner, the pill of a job), inside a window that
// ignores the strip the dock reserves: the compositor would move such a window at once when the dock
// changes edge. The window stays put; this item keeps clear of the dock (BannerPlacement) and follows
// it with the dock's own movement, on the render thread. Something that only now appears is simply
// there.
Item {
    id: place

    required property Window host
    required property int contentWidth
    // The window's first frame is on screen
    property bool presented: false
    // Not under a fullscreen window
    property bool dockVisible: true

    // Room around the content for its shadow, and for moving out of the dock's way
    readonly property int shadowMargin: 32
    readonly property int dockRoom: 120
    readonly property int topMargin: 10
    readonly property bool follows: presented && ShellState.synced

    x: (host.width - contentWidth) / 2 + placement.offsetX
    y: topMargin + placement.offsetY
    width: contentWidth
    height: host.height - topMargin

    BannerPlacement {
        id: placement

        dockEdge: ShellState.dockEdge
        dockStrip: ShellState.dockStrip
        dockVisible: place.dockVisible
                     && (ShellState.dockScreen.length === 0 || ShellState.dockScreen === place.host.screen.name)
        maximumShift: Math.max(0, (place.host.width - place.contentWidth) / 2 - place.shadowMargin)
    }

    Behavior on x {
        enabled: place.follows

        XAnimator { duration: 450; easing.type: Easing.OutQuart }
    }
    Behavior on y {
        enabled: place.follows

        YAnimator { duration: 450; easing.type: Easing.OutQuart }
    }
}
