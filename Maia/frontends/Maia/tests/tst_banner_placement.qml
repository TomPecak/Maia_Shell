import QtQuick
import QtTest

import "../shell/notifications"

// Where a banner goes for each place of the dock.
Item {
    BannerPlacement {
        id: placement

        dockStrip: 96
    }

    TestCase {
        name: "BannerPlacement"

        function init() {
            placement.dockEdge = Qt.TopEdge
            placement.dockStrip = 96
            placement.dockVisible = true
            placement.maximumShift = 60
        }

        function test_belowADockAtTheTop() {
            compare(placement.offsetY, 96)
            compare(placement.offsetX, 0)
        }

        function test_aDockAtTheBottomChangesNothing() {
            placement.dockEdge = Qt.BottomEdge
            compare(placement.offsetY, 0)
            compare(placement.offsetX, 0)
        }

        function test_inTheMiddleOfWhatIsLeftBesideADock() {
            placement.dockEdge = Qt.LeftEdge
            compare(placement.offsetX, 48)
            compare(placement.offsetY, 0)
            placement.dockEdge = Qt.RightEdge
            compare(placement.offsetX, -48)
            compare(placement.offsetY, 0)
        }

        function test_neverOutOfTheWindow() {
            placement.dockEdge = Qt.LeftEdge
            placement.maximumShift = 20
            compare(placement.offsetX, 20)
            placement.dockEdge = Qt.RightEdge
            compare(placement.offsetX, -20)
        }

        function test_aDockThatIsNotSeenIsIgnored() {
            placement.dockVisible = false
            compare(placement.offsetY, 0)
            placement.dockEdge = Qt.LeftEdge
            compare(placement.offsetX, 0)
        }
    }
}
