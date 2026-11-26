import QtQuick
import QtTest

import LumenFrontend

import "../shell/windows"

// A tray icon of the taskbar: what each button and the wheel do, the mark of attention.
Item {
    id: root

    width: 300
    height: 200

    Component {
        id: buttonComponent

        TrayIconButton {
            x: 100
            y: 80
            source: "internet-chat"
            hasMenu: true
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "TrayIconButton"
        when: windowShown

        function make(properties) {
            const button = createTemporaryObject(buttonComponent, root, properties ?? {})
            verify(button)
            waitForRendering(button)
            return button
        }

        function spy(target, name) {
            return createTemporaryObject(spyComponent, root, { target: target, signalName: name })
        }

        function test_theButtonsAndTheWheel() {
            const button = make()
            const activated = spy(button, "activated")
            const menu = spy(button, "menuRequested")
            const context = spy(button, "contextMenuRequested")
            const secondary = spy(button, "secondaryActivated")
            const scrolled = spy(button, "scrolled")
            mouseClick(button)
            compare(activated.count, 1)
            mouseClick(button, button.width / 2, button.height / 2, Qt.RightButton)
            compare(menu.count, 1)
            mouseClick(button, button.width / 2, button.height / 2, Qt.MiddleButton)
            compare(secondary.count, 1)
            mouseWheel(button, button.width / 2, button.height / 2, 0, -120)
            compare(scrolled.count, 1)
            compare(scrolled.signalArguments[0][0], -120)
            compare(scrolled.signalArguments[0][1], false)
            mouseWheel(button, button.width / 2, button.height / 2, 120, 0)
            compare(scrolled.signalArguments[1][1], true)

            button.hasMenu = false
            mouseClick(button, button.width / 2, button.height / 2, Qt.RightButton)
            compare(context.count, 1)
            button.hasMenu = true
            button.itemIsMenu = true
            mouseClick(button)
            compare(menu.count, 2)
            compare(activated.count, 1)
        }

        function test_attention() {
            const button = make()
            const dot = findChild(button, "attentionDot")
            compare(dot.opacity, 0)
            button.needsAttention = true
            tryCompare(dot, "opacity", 1)
            compare(button.Accessible.description, "needs attention")
        }
    }
}
