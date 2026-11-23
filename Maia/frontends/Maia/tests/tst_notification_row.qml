import QtQuick
import QtTest

import MaiaFrontend

import "../shell/notifications"

// One row of the notification center: a notification or the stack of an application, what a tap
// and a swipe do on each, and the header of an unfolded group.
Item {
    id: root

    width: 520
    height: 700

    function rowData(extra) {
        const data = { notificationId: 7, appName: "Mail", appIcon: "", desktopEntry: "org.mail", summary: "A message",
                       body: "Short text", time: new Date(), image: "", actions: [], actionIcons: false, files: [],
                       hasDefaultAction: false, inlineReply: false, replyPlaceholder: "", replySubmitText: "",
                       urgency: 0, originName: "", groupKey: "org.mail", groupCount: 1, groupHead: true,
                       groupExpanded: false }
        for (const key in extra)
            data[key] = extra[key]
        return data
    }

    Component {
        id: rowComponent

        NotificationRow {
            x: 40
            y: 20
            width: 420
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "NotificationRow"
        when: windowShown

        function initTestCase() {
            Qt.application.organization = "MaiaTest"
            Qt.application.domain = "maia.test"
        }

        function make(extra) {
            const row = createTemporaryObject(rowComponent, root, { model: root.rowData(extra) })
            verify(row)
            waitForRendering(row)
            return row
        }

        function spy(row, name) {
            return createTemporaryObject(spyComponent, root, { target: row, signalName: name })
        }

        function mover(row) {
            return findChild(row, "rowCard").parent
        }

        function swipe(row, distance) {
            const y = mover(row).y + 40
            mousePress(row, 200, y)
            for (let i = 1; i <= 8; ++i) {
                mouseMove(row, 200 + distance * i / 8, y)
                wait(16)
            }
            wait(120)
            mouseRelease(row, 200 + distance, y)
        }

        function test_aSingleOneIsNotAStack() {
            const row = make()
            verify(!row.stacked)
            verify(!row.hasHeader)
            compare(findChild(row, "cardTitle").text, "A message")
            verify(!findChild(row, "cardMeta").text.includes("more"))
        }

        function test_aStackShowsHowManyMore() {
            const row = make({ groupCount: 4 })
            verify(row.stacked)
            verify(findChild(row, "cardMeta").text.includes("3 more"))
            verify(findChild(row, "stackPlate").visible)
            verify(row.height > mover(row).height + 10)
        }

        function test_aTapOnAStackUnfoldsIt() {
            const row = make({ groupCount: 3, hasDefaultAction: true })
            const toggled = spy(row, "groupToggled")
            const invoked = spy(row, "defaultInvoked")
            mouseClick(row, 150, 30)
            compare(toggled.count, 1)
            compare(toggled.signalArguments[0][0], "org.mail")
            compare(invoked.count, 0)
        }

        function test_aTapRunsTheDefaultAction() {
            const row = make({ hasDefaultAction: true })
            const invoked = spy(row, "defaultInvoked")
            mouseClick(row, 150, 30)
            compare(invoked.count, 1)
        }

        function test_aTapWithoutDefaultExpands() {
            const row = make({ actions: [{ key: "a", label: "Open" }] })
            mouseClick(row, 150, 30)
            verify(row.card.expanded)
            tryVerify(() => findChild(row, "action:a") !== null)
        }

        function test_aSwipeClearsOne() {
            const row = make()
            const dismissed = spy(row, "dismissed")
            swipe(row, 220)
            tryCompare(dismissed, "count", 1)
        }

        function test_aSwipeTheOtherWayToo() {
            const row = make()
            const dismissed = spy(row, "dismissed")
            swipe(row, -180)
            tryCompare(dismissed, "count", 1)
        }

        function test_aSwipeOnAStackClearsTheGroup() {
            const row = make({ groupCount: 3 })
            const cleared = spy(row, "groupCleared")
            const dismissed = spy(row, "dismissed")
            swipe(row, 220)
            tryCompare(cleared, "count", 1)
            compare(cleared.signalArguments[0][0], "org.mail")
            compare(dismissed.count, 0)
        }

        function test_aShortSwipeComesBack() {
            const row = make()
            const dismissed = spy(row, "dismissed")
            swipe(row, 40)
            tryVerify(() => mover(row).x === 0)
            compare(dismissed.count, 0)
        }

        function test_aClearedRowThatStaysComesBack() {
            const row = make()
            swipe(row, 240)
            tryVerify(() => Math.abs(mover(row).x) > 400)
            tryVerify(() => mover(row).x === 0, 2500)
        }

        function test_anUnfoldedGroupHasAHeader() {
            const row = make({ groupCount: 3, groupExpanded: true })
            verify(row.hasHeader)
            verify(!row.stacked)
            compare(findChild(row, "groupName").text, "Mail")
            const toggled = spy(row, "groupToggled")
            const cleared = spy(row, "groupCleared")
            mouseClick(findChild(row, "showLessButton"))
            compare(toggled.count, 1)
            mouseClick(findChild(row, "clearGroupButton"))
            compare(cleared.count, 1)
        }

        function test_theRestOfAGroupHasNoHeader() {
            const row = make({ groupCount: 3, groupExpanded: true, groupHead: false })
            verify(!row.hasHeader)
            verify(!row.stacked)
            compare(findChild(row, "groupName").parent.height, 0)
        }

        function test_timeIsCountedFromNow() {
            const now = new Date()
            const row = make({ time: new Date(now.getTime() - 5 * 60000) })
            row.now = now
            verify(findChild(row, "cardMeta").text.includes("5 min ago"))
            row.now = new Date(now.getTime() + 55 * 60000 + 1000)
            verify(!findChild(row, "cardMeta").text.includes("min ago"))
        }

        function test_theExpandedPartIsNotCreatedAhead() {
            const row = make({ actions: [{ key: "a", label: "Open" }] })
            wait(60)
            compare(findChild(row, "action:a"), null)
        }
    }
}
