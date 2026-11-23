import QtQuick
import QtTest

import MaiaFrontend

import "../shell/jobs"

// The pill of a job at the top of the screen: compact, unfolded, swiped away, stepping aside.
Item {
    id: root

    width: 520
    height: 500

    function job(extra) {
        const j = { jobId: 3, appName: "Dolphin", appIcon: "", desktopEntry: "org.kde.dolphin", title: "Copying",
                    infoMessage: "report.pdf", state: 0, percent: 40, processedBytes: 400, totalBytes: 1000,
                    processedFiles: 1, totalFiles: 3, speed: 100, destination: "file:///home/a",
                    errorText: "", ownerGone: false, killable: true, suspendable: true }
        for (const key in extra)
            j[key] = extra[key]
        return j
    }

    Component {
        id: pillComponent

        JobPill {
            x: 40
            y: 30
            width: 420
        }
    }

    Component {
        id: spyComponent

        SignalSpy {
        }
    }

    TestCase {
        name: "JobPill"
        when: windowShown

        function initTestCase() {
            Qt.application.organization = "MaiaTest"
            Qt.application.domain = "maia.test"
        }

        function make(extra, others) {
            const pill = createTemporaryObject(pillComponent, root, { job: root.job(extra), others: others ?? 0 })
            verify(pill)
            tryVerify(() => mover(pill).opacity === 1 && mover(pill).y === 0)
            return pill
        }

        function spy(pill, name) {
            return createTemporaryObject(spyComponent, root, { target: pill, signalName: name })
        }

        function mover(pill) {
            return findChild(pill, "jobPillPlate").parent
        }

        function center(pill) {
            return (pill.width) / 2
        }

        // Unfolded, at full height, with the card created
        function unfold(pill) {
            mouseClick(pill, center(pill), 24)
            verify(pill.expanded)
            tryVerify(() => findChild(pill, "jobTitle") !== null)
            tryVerify(() => mover(pill).height === pill.restingHeight && pill.restingHeight > 100)
            tryVerify(() => mover(pill).width === pill.width)
            waitForRendering(pill)
        }

        function test_compactSaysWhatAndHowFar() {
            const pill = make()
            compare(findChild(pill, "jobPillTitle").text, "Copying")
            compare(findChild(pill, "jobPillState").text, "40 %")
            verify(!findChild(pill, "jobPillMore").visible)
            compare(pill.restingHeight, 52)
            verify(pill.restingWidth < pill.width)
        }

        function test_itKeepsItsSizeWhileCounting() {
            const pill = make({ percent: 9 })
            const width = pill.restingWidth
            pill.job = root.job({ percent: 10 })
            compare(pill.restingWidth, width)
            pill.job = root.job({ percent: 100 })
            compare(pill.restingWidth, width)
        }

        function test_itShowsHowManyMore() {
            const pill = make({}, 2)
            verify(findChild(pill, "jobPillMore").visible)
        }

        function test_aTapUnfoldsAndFolds() {
            const pill = make()
            unfold(pill)
            verify(pill.held)
            verify(findChild(pill, "jobPauseButton").visible)
            mouseClick(pill, 60, 20)
            verify(!pill.expanded)
            tryCompare(mover(pill), "height", 52)
        }

        function test_theControlsOfTheCardWork() {
            const pill = make()
            unfold(pill)
            const paused = spy(pill, "pauseRequested")
            const cancelled = spy(pill, "cancelRequested")
            mouseClick(findChild(pill, "jobPauseButton"))
            compare(paused.count, 1)
            verify(pill.expanded)
            const cancel = findChild(pill, "jobCancelButton")
            mouseClick(cancel)
            compare(cancelled.count, 0)
            mouseClick(cancel)
            compare(cancelled.count, 1)
        }

        function test_moreOpensTheList() {
            const pill = make({}, 2)
            unfold(pill)
            const more = spy(pill, "moreRequested")
            mouseClick(findChild(pill, "jobPillMoreButton"))
            compare(more.count, 1)
        }

        function test_aSwipeUpPutsItAway() {
            const pill = make()
            const away = spy(pill, "swipedAway")
            mouseDrag(pill, center(pill), 40, 0, -38, Qt.LeftButton, Qt.NoModifier, 20)
            compare(away.count, 1)
            verify(!pill.expanded)
        }

        function test_itStepsAsideForABanner() {
            const pill = make()
            const cover = mover(pill).parent
            pill.covered = true
            tryCompare(cover, "opacity", 0)
            verify(!cover.enabled)
            pill.covered = false
            tryCompare(cover, "opacity", 1)
        }

        function test_anEndedJobShowsHowItWent() {
            const pill = make({ state: 2, percent: 100 })
            compare(findChild(pill, "jobPillState").text, "Done")
            const failed = make({ state: 3 })
            compare(findChild(failed, "jobPillState").text, "Failed")
        }

        function test_itWaitsForTheFirstFrame() {
            const pill = createTemporaryObject(pillComponent, root, { job: root.job(), ready: false })
            wait(60)
            compare(mover(pill).opacity, 0)
            pill.ready = true
            tryCompare(mover(pill), "opacity", 1)
        }

        function test_leavesAndSaysSo() {
            for (const replaced of [false, true]) {
                const pill = make()
                const left = spy(pill, "leaveFinished")
                pill.leave(replaced)
                pill.leave(replaced)
                verify(pill.leaving)
                tryCompare(left, "count", 1)
                wait(40)
                compare(left.count, 1)
            }
        }

        function test_leavingBeforeComingIn() {
            const pill = createTemporaryObject(pillComponent, root, { job: root.job(), ready: false })
            const left = spy(pill, "leaveFinished")
            pill.leave(false)
            compare(left.count, 1)
        }
    }
}
