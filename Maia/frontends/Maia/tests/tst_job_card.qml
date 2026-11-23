import QtQuick
import QtTest

import MaiaFrontend

import "../shell/jobs"

// The ring, the bar and the card of a job: what they show in each state and what they ask for.
Item {
    id: root

    width: 520
    height: 500

    function job(extra) {
        const j = { jobId: 3, appName: "Dolphin", appIcon: "", desktopEntry: "org.kde.dolphin", title: "Copying",
                    infoMessage: "report.pdf", state: 0, percent: 40, processedBytes: 400, totalBytes: 1000,
                    processedFiles: 1, totalFiles: 3, speed: 100, destination: "file:///home/a/My Files",
                    errorText: "", ownerGone: false, killable: true, suspendable: true }
        for (const key in extra)
            j[key] = extra[key]
        return j
    }

    Component {
        id: cardComponent

        JobCard {
            x: 40
            y: 20
            width: 420
            height: implicitHeight
        }
    }

    Component {
        id: ringComponent

        JobRing {
        }
    }

    Component {
        id: barComponent

        JobBar {
            width: 200
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "JobCard"
        when: windowShown

        function initTestCase() {
            Qt.application.organization = "MaiaTest"
            Qt.application.domain = "maia.test"
        }

        function make(extra) {
            const card = createTemporaryObject(cardComponent, root, { job: root.job(extra) })
            verify(card)
            waitForRendering(card)
            return card
        }

        function spy(card, name) {
            return createTemporaryObject(spyComponent, root, { target: card, signalName: name })
        }

        function find(card, name) {
            return findChild(card, name)
        }

        function test_runningShowsItsProgressAndControls() {
            const card = make()
            compare(find(card, "jobTitle").text, "Copying")
            compare(find(card, "jobInfo").text, "report.pdf")
            compare(find(card, "jobPercent").text, "40 %")
            verify(find(card, "jobBar").visible)
            verify(find(card, "jobPauseButton").visible)
            verify(find(card, "jobCancelButton").visible)
            verify(!find(card, "jobFolderButton").visible)
            verify(!find(card, "jobCloseButton").visible)
        }

        function test_withoutPermissionsNoControls() {
            const card = make({ killable: false, suspendable: false })
            verify(!find(card, "jobPauseButton").visible)
            verify(!find(card, "jobCancelButton").visible)
        }

        function test_pauseAndResume() {
            const card = make()
            const paused = spy(card, "pauseRequested")
            mouseClick(find(card, "jobPauseButton"))
            compare(paused.signalArguments[0][0], true)
            card.job = root.job({ state: 1 })
            compare(find(card, "jobPauseButton").text, "Resume")
            mouseClick(find(card, "jobPauseButton"))
            compare(paused.signalArguments[1][0], false)
        }

        function test_cancelAsksOnce() {
            const card = make()
            const cancelled = spy(card, "cancelRequested")
            const button = find(card, "jobCancelButton")
            mouseClick(button)
            compare(cancelled.count, 0)
            verify(card.cancelArmed)
            compare(button.text, "Really cancel?")
            mouseClick(button)
            compare(cancelled.count, 1)
            verify(!card.cancelArmed)
        }

        function test_theQuestionGoesAwayByItself() {
            const card = make()
            mouseClick(find(card, "jobCancelButton"))
            verify(card.cancelArmed)
            tryVerify(() => !card.cancelArmed, 3600)
        }

        function test_finishedOffersItsFolder() {
            const card = make({ state: 2, percent: 100 })
            verify(!find(card, "jobBar").visible)
            verify(!find(card, "jobPauseButton").visible)
            verify(find(card, "jobCloseButton").visible)
            verify(find(card, "jobDetail").text.startsWith("Done"))
            const folder = spy(card, "openFolderRequested")
            mouseClick(find(card, "jobFolderButton"))
            compare(folder.signalArguments[0][0], "file:///home/a/My%20Files")
            const dismissed = spy(card, "dismissed")
            mouseClick(find(card, "jobCloseButton"))
            compare(dismissed.count, 1)
        }

        function test_failedSaysWhy() {
            const card = make({ state: 3, errorText: "The disk is full" })
            compare(find(card, "jobDetail").text, "The disk is full")
            verify(!find(card, "jobFolderButton").visible)
            verify(find(card, "jobCloseButton").visible)
        }

        function test_theNumbersAreReadOnceASecond() {
            const card = make()
            const before = card.detail
            card.job = root.job({ processedBytes: 900 })
            compare(card.detail, before)
            tryVerify(() => card.detail !== before, 1300)
        }

        function test_createdUnseenItHasItsButtonsWhenShown() {
            const card = createTemporaryObject(cardComponent, root, { job: root.job(), visible: false })
            card.visible = true
            verify(find(card, "jobPauseButton").visible)
            verify(find(card, "jobCancelButton").visible)
            verify(find(card, "jobPauseButton").width > 100)
        }

        function test_unseenItDoesNoWork() {
            const card = make()
            const before = card.detail
            card.visible = false
            card.job = root.job({ processedBytes: 900 })
            wait(1200)
            compare(card.detail, before)
            card.visible = true
            verify(card.detail !== before)
        }

        function test_anEndedJobIsReadAtOnce() {
            const card = make()
            card.job = root.job({ state: 2, percent: 100 })
            tryVerify(() => card.detail.startsWith("Done"), 200)
        }

        function test_ring_data() {
            return [
                { tag: "share", percent: 40, jobState: 0, share: 0.4, glyph: "" },
                { tag: "unknown", percent: -1, jobState: 0, share: 0.25, glyph: "" },
                { tag: "paused", percent: 40, jobState: 1, share: 0.4, glyph: "media-playback-pause-symbolic" },
                { tag: "done", percent: 40, jobState: 2, share: 1, glyph: "checkmark-symbolic" },
                { tag: "failed", percent: 10, jobState: 3, share: 1, glyph: "window-close-symbolic" },
            ]
        }

        function test_ring(row) {
            const ring = createTemporaryObject(ringComponent, root, { percent: row.percent, jobState: row.jobState })
            fuzzyCompare(ring.share, row.share, 0.001)
            compare(ring.glyph, row.glyph)
        }

        function test_barSlidesItsFill() {
            const bar = createTemporaryObject(barComponent, root, { percent: 25 })
            const fill = findChild(bar, "jobBarFill")
            tryCompare(fill, "x", -150)
            bar.percent = 100
            tryCompare(fill, "x", 0)
            verify(!findChild(bar, "jobBarPiece").visible)
        }

        function test_anUnknownShareMovesAPiece() {
            const bar = createTemporaryObject(barComponent, root, { percent: -1 })
            verify(findChild(bar, "jobBarPiece").visible)
            verify(!findChild(bar, "jobBarFill").visible)
        }
    }
}
