import QtQuick
import QtQuick.Effects

// Menu surface in the style of iPadOS: frosted glass (the wallpaper below, blurred and
// brightened), large corner radius and a soft wide shadow. The items (MenuItem,
// MenuSeparator, MenuGroupSeparator) are stacked in a column.
//
// The panel has to be a direct child of the window content, its x / y are used to cut
// the right part of the wallpaper out.
//
// It opens with a springy zoom out of originX / originY (the click point) and closes
// with a short shrink and fade. While a submenu covers it, it is pushed back (dimmed).
Item {
    id: panel

    default property alias content: column.data
    property bool open: false
    // Hidden full-screen copy of the wallpaper, the source of the frosted glass
    property Item backdropSource: null
    // Point the panel grows from, in the panel coordinates
    property real originX: 0
    property real originY: 0
    // Scale the panel grows from
    property real closedScale: 0.5
    // A submenu lies over the panel
    property bool pushedBack: false

    readonly property int radius: 14
    readonly property int padding: 6
    readonly property bool hovered: hoverHandler.hovered

    property real openScale: closedScale
    property real pushProgress: pushedBack ? 1 : 0

    implicitWidth: 260
    implicitHeight: column.implicitHeight + 2 * padding
    width: implicitWidth
    height: implicitHeight

    opacity: 0
    visible: opacity > 0

    transform: [
        Scale {
            origin.x: panel.originX
            origin.y: panel.originY
            xScale: panel.openScale
            yScale: panel.openScale
        },
        Scale {
            origin.x: panel.width / 2
            origin.y: panel.height / 2
            xScale: 1 - 0.04 * panel.pushProgress
            yScale: 1 - 0.04 * panel.pushProgress
        }
    ]

    Behavior on pushProgress {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    onOpenChanged: {
        if (open) {
            replay()
        } else {
            openAnimation.stop()
            closeAnimation.restart()
        }
    }

    // Plays the opening animation from the start, e.g. after the menu moved to a new position
    function replay() {
        if (!open)
            return
        closeAnimation.stop()
        openScale = closedScale
        opacity = 0
        openAnimation.restart()
    }

    ParallelAnimation {
        id: openAnimation

        // Spring like: a fast start with a small overshoot
        NumberAnimation {
            target: panel
            property: "openScale"
            to: 1
            duration: 420
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
        }
        NumberAnimation {
            target: panel
            property: "opacity"
            to: 1
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: closeAnimation

        NumberAnimation {
            target: panel
            property: "openScale"
            to: 0.85
            duration: 180
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: panel
            property: "opacity"
            to: 0
            duration: 180
            easing.type: Easing.InCubic
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    RectangularShadow {
        anchors.fill: parent
        radius: panel.radius
        offset.y: 12
        blur: 48
        spread: 0
        color: Qt.rgba(0, 0, 0, 0.22)
    }

    // --- Frosted glass ---

    // The wallpaper part below the panel, with a margin so the blur has no dark edges
    ShaderEffectSource {
        id: backdrop

        readonly property int margin: 48

        x: -margin
        y: -margin
        width: panel.width + 2 * margin
        height: panel.height + 2 * margin
        visible: false
        sourceItem: panel.backdropSource
        sourceRect: Qt.rect(panel.x - margin, panel.y - margin, width, height)
    }

    Item {
        id: glassMask

        anchors.fill: backdrop
        visible: false
        layer.enabled: true

        Rectangle {
            x: backdrop.margin
            y: backdrop.margin
            width: panel.width
            height: panel.height
            radius: panel.radius
        }
    }

    MultiEffect {
        anchors.fill: backdrop
        source: backdrop
        visible: panel.backdropSource !== null
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.35
        maskEnabled: true
        maskSource: glassMask
    }

    // Brightening layer of the material
    Rectangle {
        anchors.fill: parent
        radius: panel.radius
        color: Qt.rgba(0.97, 0.97, 0.98, panel.backdropSource ? 0.76 : 0.96)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.45)
    }

    // Clicks on the padding and separators do not fall through the menu
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Column {
        id: column

        y: panel.padding
        width: panel.width
    }

    // Dimming while a submenu lies over the panel
    Rectangle {
        anchors.fill: parent
        radius: panel.radius
        color: Qt.rgba(0, 0, 0, 0.12)
        opacity: panel.pushProgress
        visible: opacity > 0
    }
}
