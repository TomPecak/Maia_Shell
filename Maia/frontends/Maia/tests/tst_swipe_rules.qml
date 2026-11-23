import QtQuick
import QtTest

import "../shell/notifications/SwipeRules.js" as SwipeRules

// Where a swiped row goes when the finger lifts.
Item {
    TestCase {
        name: "SwipeRules"

        readonly property int reveal: 112
        readonly property int commit: 294

        function go(offset, velocity) {
            return SwipeRules.settle(offset, velocity, reveal, commit)
        }

        function test_slowly_theNearerPlaceWins_data() {
            return [
                { tag: "barely moved", offset: 10, expected: SwipeRules.closed },
                { tag: "just before half", offset: 55, expected: SwipeRules.closed },
                { tag: "half", offset: 56, expected: SwipeRules.revealed },
                { tag: "at the button", offset: 112, expected: SwipeRules.revealed },
                { tag: "well past it", offset: 250, expected: SwipeRules.revealed },
                { tag: "just before deleting", offset: 293, expected: SwipeRules.revealed },
            ]
        }

        function test_slowly_theNearerPlaceWins(row) {
            compare(go(row.offset, 0), row.expected)
        }

        function test_onlyADeliberateDragDeletes() {
            compare(go(294, 0), SwipeRules.clear)
            compare(go(420, 0), SwipeRules.clear)
        }

        function test_aFlickNeverDeletes() {
            for (const offset of [12, 40, 112, 200, 293])
                compare(go(offset, -5000), SwipeRules.revealed)
        }

        function test_aTinyFlickIsNotMeant() {
            compare(go(6, -5000), SwipeRules.closed)
        }

        function test_aFlickBackCloses() {
            for (const offset of [12, 112, 200, 293])
                compare(go(offset, 5000), SwipeRules.closed)
        }

        function test_toTheRightNothingHappens() {
            compare(go(0, 5000), SwipeRules.closed)
            compare(go(0, -5000), SwipeRules.closed)
        }
    }
}
