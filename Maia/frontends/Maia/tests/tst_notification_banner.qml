import QtQuick
import QtTest

import MaiaFrontend

import "../shell/notifications"

// A notification banner on its own: what it shows compact and expanded, its gestures (tap, swipe,
// pull, long press), the buttons, the answer, the files and its way out.
Item {
    id: root

    width: 520
    height: 760

    Component {
        id: bannerComponent

        NotificationBanner {
            x: 40
            y: 20
            width: 420
            appName: "Mail"
            title: "A new message"
            body: "Short text"
            time: new Date()
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    function file(name, extra) {
        const f = { url: "file:///tmp/" + name, name: name, mimeType: "application/octet-stream",
                    iconName: "application-octet-stream", genericIconName: "text-x-generic",
                    preview: "", local: true, exists: true, image: false }
        for (const key in extra)
            f[key] = extra[key]
        return f
    }

    TestCase {
        name: "NotificationBanner"
        when: windowShown

        function initTestCase() {
            // Theme keeps its mode in Settings (a temporary directory here)
            Qt.application.organization = "MaiaTest"
            Qt.application.domain = "maia.test"
        }

        // Expanded and at its full height: what is below the fold takes input only then
        function expand(banner) {
            banner.expanded = true
            tryVerify(() => mover(banner).height === banner.height && banner.height > 100)
            waitForRendering(banner)
        }

        function make(properties) {
            const banner = createTemporaryObject(bannerComponent, root, properties ?? {})
            verify(banner)
            tryVerify(() => mover(banner).opacity === 1 && mover(banner).y === 0)
            return banner
        }

        function spy(banner, name) {
            return createTemporaryObject(spyComponent, root, { target: banner, signalName: name })
        }

        function find(banner, name) {
            return findChild(banner, name)
        }

        function mover(banner) {
            return findChild(banner, "bannerPlate").parent
        }

        function test_compactShowsTheText() {
            const banner = make()
            compare(find(banner, "cardTitle").text, "A new message")
            verify(find(banner, "cardMeta").text.startsWith("Mail · "))
            verify(!banner.expanded)
            verify(!banner.canExpand)
            verify(!find(banner, "expandButton").visible)
        }

        function test_longTextCanBeExpanded() {
            const banner = make({ body: "A very long line of text. ".repeat(30) })
            tryVerify(() => banner.canExpand)
            const compact = banner.height
            mouseClick(find(banner, "expandButton"))
            verify(banner.expanded)
            tryVerify(() => banner.height > compact)
            verify(banner.held)
            mouseClick(find(banner, "expandButton"))
            verify(!banner.expanded)
            tryCompare(banner, "height", compact)
        }

        function test_longTextScrollsInsteadOfGrowingWithoutEnd() {
            const banner = make({ body: "A very long line of text. ".repeat(400) })
            banner.expanded = true
            tryVerify(() => banner.height < 420)
        }

        function test_tapRunsTheDefaultAction() {
            const banner = make({ hasDefaultAction: true })
            const invoked = spy(banner, "defaultInvoked")
            mouseClick(banner, 150, 30)
            compare(invoked.count, 1)
            verify(!banner.expanded)
        }

        function test_tapWithoutDefaultExpands() {
            const banner = make({ actions: [{ key: "a", label: "Open" }] })
            mouseClick(banner, 150, 30)
            verify(banner.expanded)
        }

        function test_swipeUpSendsItAway() {
            const banner = make({ hasDefaultAction: true })
            const away = spy(banner, "swipedAway")
            const invoked = spy(banner, "defaultInvoked")
            mouseDrag(banner, 200, 50, 0, -60, Qt.LeftButton, Qt.NoModifier, 20)
            compare(away.count, 1)
            compare(invoked.count, 0)
        }

        function test_aTallBannerSwipesAwayFromTheTopEdge() {
            const banner = make({ body: "A very long line of text. ".repeat(12),
                                  actions: [{ key: "a", label: "Open" }] })
            expand(banner)
            verify(banner.height > 160)
            const away = spy(banner, "swipedAway")
            mousePress(banner, 200, 44)
            for (let y = 40; y >= 4; y -= 4) {
                mouseMove(banner, 200, y)
                wait(30)
            }
            wait(120)
            mouseRelease(banner, 200, 4)
            compare(away.count, 1)
        }

        function test_aShortSwipeComesBack() {
            const banner = make()
            const away = spy(banner, "swipedAway")
            mousePress(banner, 200, 50)
            for (let y = 48; y >= 38; y -= 2) {
                mouseMove(banner, 200, y)
                wait(40)
            }
            wait(100)
            mouseRelease(banner, 200, 38)
            compare(away.count, 0)
            tryVerify(() => mover(banner).y === 0)
        }

        function test_pullDownExpands() {
            const banner = make({ actions: [{ key: "a", label: "Open" }] })
            mousePress(banner, 200, 30)
            for (let y = 40; y <= 130; y += 10) {
                mouseMove(banner, 200, y)
                wait(16)
            }
            verify(mover(banner).y <= 48)
            wait(80)
            mouseRelease(banner, 200, 130)
            verify(banner.expanded)
            tryVerify(() => mover(banner).y === 0)
        }

        function test_longPressExpands() {
            const banner = make({ actions: [{ key: "a", label: "Open" }], hasDefaultAction: true })
            const invoked = spy(banner, "defaultInvoked")
            mousePress(banner, 200, 30)
            tryVerify(() => banner.expanded, 1500)
            mouseRelease(banner, 200, 30)
            compare(invoked.count, 0)
        }

        function test_actionsAreShownExpanded() {
            const banner = make({ actions: [{ key: "yes", label: "Accept" }, { key: "no", label: "Decline" }] })
            const hidden = find(banner, "action:yes")
            verify(!hidden || !hidden.visible)
            expand(banner)
            const invoked = spy(banner, "actionInvoked")
            mouseClick(find(banner, "action:no"))
            compare(invoked.count, 1)
            compare(invoked.signalArguments[0][0], "no")
        }

        function test_mediaKeysAreIcons() {
            const banner = make({ actionIcons: true, actions: [{ key: "media-playback-pause", label: "Pause" }] })
            banner.expanded = true
            tryVerify(() => find(banner, "action:media-playback-pause") !== null)
            const key = find(banner, "action:media-playback-pause")
            verify(key.round)
            verify(key.glyph.toString().endsWith("media-playback-pause-symbolic.svg"))
            compare(key.Accessible.name, "Pause")
        }

        function test_replySendsAndCloses() {
            const banner = make({ inlineReply: true })
            expand(banner)
            const replied = spy(banner, "replied")
            mouseClick(find(banner, "replyButton"))
            verify(banner.replying)
            const field = find(banner, "replyField")
            field.input.text = "On my way"
            field.send()
            compare(replied.count, 1)
            compare(replied.signalArguments[0][0], "On my way")
            verify(!banner.replying)
            verify(!banner.expanded)
        }

        function test_theKeyboardOnlyForABannerTheUserOpened() {
            const banner = make({ urgency: 2, inlineReply: true, actions: [{ key: "a", label: "Fix" }] })
            verify(banner.expanded)
            verify(!banner.wantsKeyboard)
            const plain = make({ inlineReply: true })
            verify(!plain.wantsKeyboard)
            plain.setExpanded(true)
            verify(plain.wantsKeyboard)
            plain.setExpanded(false)
            verify(!plain.wantsKeyboard)
        }

        function test_anEmptyReplyIsNotSent() {
            const banner = make({ inlineReply: true })
            banner.expanded = true
            tryVerify(() => find(banner, "replyField") !== null)
            const replied = spy(banner, "replied")
            const field = find(banner, "replyField")
            field.input.text = "   "
            field.send()
            compare(replied.count, 0)
        }

        function test_noSwipeWhileReplying() {
            const banner = make({ inlineReply: true })
            banner.openReply()
            tryVerify(() => banner.replying)
            const away = spy(banner, "swipedAway")
            mouseDrag(banner, 200, 30, 0, -120, Qt.LeftButton, Qt.NoModifier, 20)
            compare(away.count, 0)
        }

        function test_aCriticalOneStaysOpenWithItsActions() {
            const banner = make({ urgency: 2, actions: [{ key: "a", label: "Fix" }] })
            verify(banner.critical)
            verify(banner.expanded)
            verify(banner.held)
            verify(find(banner, "closeButton").visible)
            verify(!find(banner, "expandButton").visible)
        }

        function test_aFileOpensAndAGoneOneDoesNot() {
            const banner = make({ files: [root.file("a.txt"), root.file("gone.txt", { exists: false })] })
            expand(banner)
            const opened = spy(banner, "fileOpened")
            const rows = []
            const column = find(banner, "fileRow").parent
            for (let i = 0; i < column.children.length; ++i) {
                if (column.children[i].objectName === "fileRow")
                    rows.push(column.children[i])
            }
            compare(rows.length, 2)
            mouseClick(rows[1], 120, 26)
            compare(opened.count, 0)
            mouseClick(rows[0], 120, 26)
            compare(opened.count, 1)
            compare(opened.signalArguments[0][0], "file:///tmp/a.txt")
        }

        function test_aFileTapIsNotTheDefaultAction() {
            const banner = make({ hasDefaultAction: true, files: [root.file("a.txt")] })
            expand(banner)
            const invoked = spy(banner, "defaultInvoked")
            mouseClick(find(banner, "fileRow"), 120, 26)
            compare(invoked.count, 0)
        }

        function test_waitsForTheFirstFrame() {
            const banner = createTemporaryObject(bannerComponent, root, { ready: false })
            wait(60)
            compare(mover(banner).opacity, 0)
            banner.ready = true
            tryCompare(mover(banner), "opacity", 1)
        }

        function test_leavesAndSaysSo() {
            for (const replaced of [false, true]) {
                const banner = make()
                const left = spy(banner, "leaveFinished")
                banner.leave(replaced)
                verify(banner.leaving)
                banner.leave(replaced)
                tryCompare(left, "count", 1)
                wait(40)
                compare(left.count, 1)
            }
        }

        function test_leavingBeforeComingIn() {
            const banner = createTemporaryObject(bannerComponent, root, { ready: false })
            const left = spy(banner, "leaveFinished")
            banner.leave(false)
            compare(left.count, 1)
        }
    }
}
