import QtQuick
import QtTest

import MaiaFrontend

import "../shell/tray"

// The tray's plate in the dock strip: its places, "+N", the input of its icons, coming and going.
Item {
    id: root

    width: 600
    height: 500

    function item(id, extra) {
        const i = { itemId: id, currentIconSource: "internet-chat", currentIconIsMask: false, overlayIconSource: "", needsAttention: false,
                    hasMenu: true, itemIsMenu: false, title: "Item " + id, appName: "App " + id }
        for (const key in extra)
            i[key] = extra[key]
        return i
    }

    ListModel {
        id: trayItems
    }

    Component {
        id: buttonComponent

        TrayButton {
            x: 300
            y: 40
            items: trayItems
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "TrayButton"
        when: windowShown

        function init() {
            trayItems.clear()
        }

        function make(count, total, properties) {
            trayItems.clear()
            for (let i = 1; i <= count; ++i)
                trayItems.append(root.item(i, {}))
            const props = { totalCount: total ?? count }
            for (const key in properties)
                props[key] = properties[key]
            const button = createTemporaryObject(buttonComponent, root, props)
            verify(button)
            return button
        }

        function spy(button, name) {
            return createTemporaryObject(spyComponent, root, { target: button, signalName: name })
        }

        function icons(button) {
            const list = []
            const find = item => {
                for (let i = 0; i < item.children.length; ++i) {
                    const child = item.children[i]
                    if (child.objectName === "trayIcon" && child.visible)
                        list.push(child)
                    find(child)
                }
            }
            find(button)
            return list
        }

        function test_noItemsNoPlate() {
            const button = make(0, 0)
            verify(!button.visible)
            button.totalCount = 1
            trayItems.append(root.item(1, {}))
            tryVerify(() => button.visible)
            button.totalCount = 0
            trayItems.clear()
            tryVerify(() => !button.visible)
        }

        function test_fourPlacesAndPlusN() {
            const four = make(4, 4)
            compare(four.capacity, 4)
            compare(four.moreCount, 0)
            verify(!findChild(four, "trayMore").parent.wanted)
            four.destroy()

            // Seven items: three of them on the plate (the model keeps to capacity), "+4"
            const seven = make(3, 7)
            compare(seven.capacity, 3)
            compare(seven.moreCount, 4)
            tryCompare(findChild(seven, "trayMore"), "text", "+4")
            verify(findChild(seven, "trayMore").parent.wanted)
        }

        function test_theLengthFollowsTheIcons() {
            const button = make(1, 1, { edge: Qt.BottomEdge, crossSize: 52 })
            tryVerify(() => button.height === 52)
            const one = button.width
            trayItems.append(root.item(2, {}))
            button.totalCount = 2
            tryVerify(() => button.width > one + 30)
            // Along a vertical strip it grows downwards, as wide as the clock
            button.destroy()
            const vertical = make(2, 2, { edge: Qt.LeftEdge, crossSize: 72 })
            tryVerify(() => vertical.width === 72 && vertical.height > 70)
        }

        function test_clicksOfAnIcon() {
            const button = make(1, 1)
            waitForRendering(button)
            const icon = icons(button)[0]
            verify(icon)
            const activated = spy(button, "activated")
            const menu = spy(button, "menuRequested")
            const context = spy(button, "contextMenuRequested")
            const secondary = spy(button, "secondaryActivated")
            const scrolled = spy(button, "scrolled")

            mouseClick(icon)
            compare(activated.count, 1)
            compare(activated.signalArguments[0][0], 1)
            mouseClick(icon, icon.width / 2, icon.height / 2, Qt.RightButton)
            compare(menu.count, 1)
            mouseClick(icon, icon.width / 2, icon.height / 2, Qt.MiddleButton)
            compare(secondary.count, 1)
            // A long press is the menu, not a click
            mousePress(icon)
            tryCompare(menu, "count", 2, 2000)
            mouseRelease(icon)
            compare(activated.count, 1)
            // Half a notch does nothing yet, the other half scrolls
            mouseWheel(icon, icon.width / 2, icon.height / 2, 0, 60)
            compare(scrolled.count, 0)
            mouseWheel(icon, icon.width / 2, icon.height / 2, 0, 60)
            compare(scrolled.count, 1)
            compare(scrolled.signalArguments[0][1], 120)

            // Without a menu: the application's own; only a menu: a click opens it
            trayItems.setProperty(0, "hasMenu", false)
            mouseClick(icon, icon.width / 2, icon.height / 2, Qt.RightButton)
            compare(context.count, 1)
            trayItems.setProperty(0, "hasMenu", true)
            trayItems.setProperty(0, "itemIsMenu", true)
            mouseClick(icon)
            compare(menu.count, 3)
            compare(activated.count, 1)
        }

        function test_attentionIsMarked() {
            const button = make(1, 1)
            waitForRendering(button)
            const dot = findChild(icons(button)[0], "attentionDot")
            tryCompare(dot, "opacity", 0)
            trayItems.setProperty(0, "needsAttention", true)
            tryCompare(dot, "opacity", 1)
        }

        function test_aTemplateIsDrawnInTheLabelsColour() {
            const button = make(1, 1)
            waitForRendering(button)
            const image = findChild(icons(button)[0], "trayIconImage")
            verify(!image.isMask)
            trayItems.setProperty(0, "currentIconIsMask", true)
            verify(image.isMask)
            compare(image.color, Theme.label)
        }

        function test_plusNOpensThePanel() {
            const button = make(3, 5)
            const more = spy(button, "moreClicked")
            const plus = findChild(button, "trayMore")
            tryVerify(() => plus.parent.opacity === 1)
            mouseClick(plus.parent)
            compare(more.count, 1)
        }
    }
}
