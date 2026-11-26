pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import MaiaFrontend
import ".."

// The system tray in the dock strip: a plate of its own next to the clock's (ControlCenterButton),
// in its style and of its width (a vertical strip) or height (a horizontal one), so that the two
// read as a pair. Below the clock along a vertical strip, to its left along a horizontal one; the
// parent places it (LayerTop.qml).
//
// - At most 4 places: the items the applications show (active, or needing attention: those first
//   when there is no room for all). With more items, or ones the applications put away (passive),
//   the last place is "+N", which opens the panel with all of them (moreClicked).
// - No items: no plate. It grows in and out like the other things of the strip, and its length
//   follows its icons with the clock's easing; an icon that comes or goes scales and fades, the
//   others slide (Animators, ListView's transitions).
// - The input of each icon: TrayIcon.qml.
//
// Data only from outside: `items` is a model with the roles of Maia.Tray's TrayItemsModel (the
// parent gives it maximumCount: capacity), `totalCount` the number of all items. The parent also
// gives the window's input region to the plate while `wanted` (a MaskArea over it).
StripItem {
    id: area

    property var items: null
    property int totalCount: 0
    // The clock plate's width (vertical) or height (horizontal)
    property real crossSize: 72
    // The panel with all items is open
    property bool checked: false
    // The item whose menu is open
    property int menuItemId: 0

    // Places for items; the parent sets the model's maximumCount to it
    readonly property int capacity: totalCount > d.places ? d.places - 1 : d.places
    readonly property int moreCount: Math.max(0, totalCount - (items ? items.count : 0))
    // Shown, also while it grows out
    readonly property bool present: d.shown

    signal activated(int itemId, Item icon)
    signal secondaryActivated(int itemId, Item icon)
    signal menuRequested(int itemId, Item icon)
    signal contextMenuRequested(int itemId, Item icon)
    signal scrolled(int itemId, int delta, bool horizontal)
    signal moreClicked()

    width: plate.width
    height: plate.height
    visible: d.shown

    // There are items: the plate is there, or coming
    readonly property bool wanted: totalCount > 0
    onWantedChanged: wanted ? d.appear() : d.disappear()
    Component.onCompleted: {
        if (wanted) {
            d.shown = true
            body.opacity = 1
            body.scale = 1
        }
    }

    Item {
        id: body

        width: plate.width
        height: plate.height
        opacity: 0
        scale: 0.6

        RectangularShadow {
            anchors.fill: plate
            radius: plate.radius
            offset.y: 2
            blur: 12
            color: Qt.rgba(0, 0, 0, 0.18)
        }

        Rectangle {
            id: plate

            readonly property real length: list.contentLength + (more.wanted ? d.slot + d.spacing : 0) + 2 * d.padding

            width: area.vertical ? area.crossSize : Math.max(d.slot + 2 * d.padding, length)
            height: area.vertical ? Math.max(d.slot + 2 * d.padding, length) : area.crossSize
            radius: 18
            color: Theme.dock
            border.width: 1
            border.color: Theme.hairline

            Behavior on width {
                enabled: !area.vertical
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                enabled: area.vertical
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
            }

            ListView {
                id: list

                readonly property real contentLength: count > 0 ? count * d.slot + (count - 1) * d.spacing : 0

                x: area.vertical ? (plate.width - d.slot) / 2 : d.padding
                y: area.vertical ? d.padding : (plate.height - d.slot) / 2
                width: area.vertical ? d.slot : contentLength
                height: area.vertical ? contentLength : d.slot
                orientation: area.vertical ? ListView.Vertical : ListView.Horizontal
                spacing: d.spacing
                interactive: false
                // Never culled while the plate catches up with a new icon
                cacheBuffer: 4 * d.slot
                model: area.items

                delegate: Item {
                    id: slot

                    required property int itemId
                    required property string currentIconSource
                    required property bool currentIconIsMask
                    required property string overlayIconSource
                    required property bool needsAttention
                    required property bool hasMenu
                    required property bool itemIsMenu
                    required property string title
                    required property string appName

                    width: d.slot
                    height: d.slot

                    TrayIcon {
                        id: trayIcon

                        objectName: "trayIcon"
                        anchors.fill: parent
                        source: slot.currentIconSource
                        isMask: slot.currentIconIsMask
                        overlaySource: slot.overlayIconSource
                        needsAttention: slot.needsAttention
                        hasMenu: slot.hasMenu
                        itemIsMenu: slot.itemIsMenu
                        name: slot.title !== "" ? slot.title : slot.appName
                        checked: area.menuItemId === slot.itemId
                        Accessible.description: slot.needsAttention ? qsTr("needs attention") : ""

                        onActivated: area.activated(slot.itemId, trayIcon)
                        onSecondaryActivated: area.secondaryActivated(slot.itemId, trayIcon)
                        onMenuRequested: area.menuRequested(slot.itemId, trayIcon)
                        onContextMenuRequested: area.contextMenuRequested(slot.itemId, trayIcon)
                        onScrolled: (delta, horizontal) => area.scrolled(slot.itemId, delta, horizontal)
                    }
                }

                // The view's transitions set their own targets: NumberAnimation (one small item)
                add: Transition {
                    NumberAnimation { property: "scale"; from: 0.4; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }
                remove: Transition {
                    NumberAnimation { property: "scale"; to: 0.4; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 240; easing.type: Easing.OutCubic }
                }
            }

            // "+N": all items, in the panel
            Item {
                id: more

                readonly property bool wanted: area.moreCount > 0

                x: area.vertical ? (plate.width - d.slot) / 2 : list.x + list.contentLength + (list.count > 0 ? d.spacing : 0)
                y: area.vertical ? list.y + list.contentLength + (list.count > 0 ? d.spacing : 0) : (plate.height - d.slot) / 2
                width: d.slot
                height: d.slot
                visible: opacity > 0 || wanted
                opacity: wanted ? 1 : 0
                scale: wanted ? 1 : 0.4

                Behavior on opacity {
                    OpacityAnimator { duration: 200; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    ScaleAnimator { duration: 260; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 9
                    color: moreArea.pressed || area.checked ? Theme.platePressed : Theme.plateHover
                    opacity: moreArea.pressed || area.checked || moreArea.containsMouse ? 1 : 0.0

                    Behavior on opacity {
                        OpacityAnimator { duration: 120; easing.type: Easing.OutQuad }
                    }
                }

                Text {
                    objectName: "trayMore"
                    anchors.centerIn: parent
                    text: "+" + area.moreCount
                    color: Theme.secondaryLabel
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }

                MouseArea {
                    id: moreArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: more.wanted
                    onClicked: area.moreClicked()
                }

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("%n more tray icons", "", area.moreCount)
                Accessible.onPressAction: area.moreClicked()
            }
        }
    }

    // Grows in and out like the power button and the clock moving to another edge (StripItem.qml)
    ParallelAnimation {
        id: appearAnimation

        ScaleAnimator { target: body; from: 0.6; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
        OpacityAnimator { target: body; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: disappearAnimation

        // Not when it was stopped because an item came back
        onFinished: d.shown = area.wanted

        ScaleAnimator { target: body; to: 0.6; duration: 160; easing.type: Easing.InCubic }
        OpacityAnimator { target: body; to: 0; duration: 160; easing.type: Easing.InCubic }
    }

    QtObject {
        id: d

        property bool shown: false
        readonly property int places: 4
        readonly property real slot: 32
        readonly property real spacing: 4
        readonly property real padding: (area.crossSize - slot) / 2 > 12 ? 12 : Math.max(6, (area.crossSize - slot) / 2)

        function appear() {
            disappearAnimation.stop()
            shown = true
            appearAnimation.restart()
        }

        function disappear() {
            appearAnimation.stop()
            disappearAnimation.restart()
        }
    }
}
