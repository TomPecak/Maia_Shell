import QtQuick
import QtTest

import MaiaFrontend

import "../shell/tray"

// What the tray opens: the panel with all items, beside the dock strip next to the plate, closed
// by a click outside or Escape; the menu of an item (without a service: it closes again).
Item {
    id: root

    width: 1000
    height: 700

    ListModel {
        id: trayItems

        ListElement { itemId: 1; currentIconSource: "internet-chat"; overlayIconSource: ""; needsAttention: false; hasMenu: true; itemIsMenu: false; title: "Chat"; appName: "Chat" }
        ListElement { itemId: 2; currentIconSource: "steam"; overlayIconSource: ""; needsAttention: true; hasMenu: true; itemIsMenu: false; title: "Steam"; appName: "Steam" }
        ListElement { itemId: 3; currentIconSource: "audio"; overlayIconSource: ""; needsAttention: false; hasMenu: false; itemIsMenu: false; title: "Music"; appName: "" }
    }

    // Where the tray's plate would be
    Rectangle {
        id: platePlace

        x: 840
        y: 640
        width: 100
        height: 52
    }

    Component {
        id: overlayComponent

        TrayOverlay {
            anchors.fill: parent
            allItems: trayItems
            plate: platePlace
            dockEdge: Qt.BottomEdge
            dockStrip: 70
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "TrayOverlay"
        when: windowShown

        function make(properties) {
            const overlay = createTemporaryObject(overlayComponent, root, properties ?? {})
            verify(overlay)
            return overlay
        }

        function spy(target, name) {
            return createTemporaryObject(spyComponent, root, { target: target, signalName: name })
        }

        function panelIcons(overlay) {
            const list = []
            const find = item => {
                for (let i = 0; i < item.children.length; ++i) {
                    const child = item.children[i]
                    if (child.objectName === "trayPanelIcon")
                        list.push(child)
                    find(child)
                }
            }
            find(overlay)
            return list
        }

        function test_thePanelLiesBesideTheStripNextToThePlate() {
            const overlay = make()
            const panel = findChild(overlay, "trayPanel")
            verify(!overlay.visible)
            overlay.panelOpen = true
            tryVerify(() => overlay.visible && panel.opacity === 1)
            compare(panelIcons(overlay).length, 3)
            // Above the strip of a bottom dock, its right side at the plate's
            compare(panel.y + panel.height, root.height - 70 - 12)
            compare(panel.x + panel.width, platePlace.x + platePlace.width)
            compare(panel.transformOrigin, Item.BottomRight)
        }

        function test_otherEdges() {
            for (const [edge, check] of [
                     [Qt.LeftEdge, p => p.x === 70 + 12],
                     [Qt.RightEdge, p => p.x + p.width === root.width - 70 - 12],
                     [Qt.TopEdge, p => p.y === 70 + 12]]) {
                const overlay = make({ dockEdge: edge })
                const panel = findChild(overlay, "trayPanel")
                overlay.panelOpen = true
                tryVerify(() => panel.opacity === 1)
                verify(check(panel), "edge " + edge + ": " + panel.x + ", " + panel.y)
                // Inside the screen
                verify(panel.x >= 12 && panel.x + panel.width <= root.width - 12)
                verify(panel.y >= 12 && panel.y + panel.height <= root.height - 12)
            }
        }

        function test_iconsOfThePanel() {
            const overlay = make({ panelOpen: true })
            tryVerify(() => findChild(overlay, "trayPanel").opacity === 1)
            const activated = spy(overlay, "activated")
            const context = spy(overlay, "contextMenuRequested")
            const icons = panelIcons(overlay)
            mouseClick(icons[1])
            compare(activated.count, 1)
            compare(activated.signalArguments[0][0], 2)
            mouseClick(icons[2], 10, 10, Qt.RightButton)
            compare(context.count, 1)
        }

        function test_aClickOutsideOrEscapeCloses() {
            const overlay = make({ panelOpen: true })
            const close = spy(overlay, "closeRequested")
            tryVerify(() => overlay.visible)
            mouseClick(overlay, 100, 100)
            compare(close.count, 1)
            keyClick(Qt.Key_Escape)
            compare(close.count, 2)
            overlay.panelOpen = false
            tryVerify(() => !overlay.visible)
        }

        function test_aMenuWithoutTheServiceClosesAgain() {
            const overlay = make()
            const closed = spy(overlay, "menuCloseRequested")
            overlay.menuAnchor = platePlace
            overlay.menuItemId = 1
            tryCompare(closed, "count", 1)
        }
    }
}
