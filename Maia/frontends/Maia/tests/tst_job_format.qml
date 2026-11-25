import QtQuick
import QtTest

import "../shell/jobs/JobFormat.js" as JobFormat

// What a job says in words.
Item {
    function job(extra) {
        const j = { title: "Copying", appName: "Dolphin", state: 0, percent: 40, processedBytes: 0, totalBytes: 0,
                    processedFiles: 0, totalFiles: 0, speed: 0, errorText: "", ownerGone: false, destination: "" }
        for (const key in extra)
            j[key] = extra[key]
        return j
    }

    TestCase {
        name: "JobFormat"

        function test_timeLeft_data() {
            return [
                { tag: "under a second", seconds: 0.2, expected: "1 s left" },
                { tag: "seconds", seconds: 20, expected: "20 s left" },
                { tag: "a minute", seconds: 60, expected: "1 min left" },
                { tag: "rounded up", seconds: 61, expected: "2 min left" },
                { tag: "never 60 min", seconds: 3599, expected: "1 h left" },
                { tag: "an hour", seconds: 3600, expected: "1 h left" },
                { tag: "hours and minutes", seconds: 3900, expected: "1 h 5 min left" },
            ]
        }

        function test_timeLeft(row) {
            compare(JobFormat.timeLeft(row.seconds), row.expected)
        }

        function test_progressSaysWhatIsKnown() {
            compare(JobFormat.progress(job()), "")
            compare(JobFormat.progress(job({ totalFiles: 5, processedFiles: 2 })), "2 of 5 files")
            const full = JobFormat.progress(job({ processedBytes: 500000000, totalBytes: 1000000000, speed: 25000000 }))
            compare(full.split(" · ").length, 3)
            verify(full.endsWith("s left") || full.endsWith("min left"), full)
        }

        function test_whatTheJobCountsTheMostTellingFirst() {
            compare(JobFormat.progress(job({ totalItems: 10, processedItems: 3 })), "3 of 10 items")
            compare(JobFormat.progress(job({ totalDirectories: 4, processedDirectories: 1 })), "1 of 4 folders")
            // Files before items, items before folders; one of anything says nothing
            compare(JobFormat.progress(job({ totalFiles: 5, processedFiles: 2, totalItems: 10 })), "2 of 5 files")
            compare(JobFormat.progress(job({ totalItems: 10, processedItems: 3, totalDirectories: 4 })), "3 of 10 items")
            compare(JobFormat.progress(job({ totalItems: 1, totalDirectories: 1 })), "")
            compare(JobFormat.progress(job({ state: 1, totalItems: 10, processedItems: 3 })), "3 of 10 items · Paused")
        }

        function test_aJobWithoutTheseValuesIsFine() {
            const old = { title: "", appName: "", state: 0, percent: -1, processedBytes: 0, totalBytes: 0,
                          processedFiles: 0, totalFiles: 0, speed: 0, errorText: "", ownerGone: false }
            compare(JobFormat.progress(old), "")
            compare(JobFormat.ended(Object.assign({}, old, { state: 2 })), "Done")
        }

        function test_pausedHasNoSpeed() {
            const text = JobFormat.progress(job({ state: 1, processedBytes: 5, totalBytes: 10, speed: 1000 }))
            verify(text.endsWith("Paused"), text)
            verify(!text.includes("left"), text)
        }

        function test_howItEnded() {
            compare(JobFormat.ended(job({ state: 2 })), "Done")
            compare(JobFormat.ended(job({ state: 2, totalFiles: 3 })), "Done, 3 files")
            compare(JobFormat.ended(job({ state: 2, totalItems: 12 })), "Done, 12 items")
            compare(JobFormat.ended(job({ state: 2, totalDirectories: 2 })), "Done, 2 folders")
            compare(JobFormat.ended(job({ state: 3, errorText: "The disk is full" })), "The disk is full")
            compare(JobFormat.ended(job({ state: 3 })), "It did not succeed.")
            compare(JobFormat.ended(job({ state: 3, ownerGone: true })), "Dolphin closed before it was done.")
        }

        function test_shortState() {
            compare(JobFormat.shortState(job()), "40 %")
            compare(JobFormat.shortState(job({ percent: -1 })), "")
            compare(JobFormat.shortState(job({ state: 1 })), "Paused")
            compare(JobFormat.shortState(job({ state: 2 })), "Done")
            compare(JobFormat.shortState(job({ state: 3 })), "Failed")
        }

        function test_aTitleIsAlwaysThere() {
            compare(JobFormat.title(job({ title: "" })), "Working")
        }

        function test_folderUrlHasNoSpaces() {
            compare(JobFormat.folderUrl("file:///home/a/My Files"), "file:///home/a/My%20Files")
            compare(JobFormat.folderUrl("file:///home/a/My%20Files"), "file:///home/a/My%20Files")
            compare(JobFormat.folderUrl("file:///a%20b/c d"), "file:///a%20b/c%20d")
        }
    }
}
