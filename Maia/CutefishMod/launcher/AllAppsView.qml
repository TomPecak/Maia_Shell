import QtQuick
import QtQuick.Layouts

import Maia.Client

import "../launcher"

ListView {
    id: control

    property bool searchMode: false

    property var sourceModel: launcherModel
    property var modelCount: sourceModel.count

    property int iconSize: 100
    property int cellWidth: iconSize + calcExtraSpacing(iconSize, control.width)
    property int cellHeight: iconSize + calcExtraSpacing(iconSize, control.height)

    property int rows: control.width / control.cellWidth
    property int columns: control.height / control.cellHeight
    property int pageCount: control.rows * control.columns

    orientation: ListView.Horizontal
    snapMode: ListView.SnapOneItem
    model: Math.ceil(control.modelCount / control.pageCount)

    maximumFlickVelocity: 10000
    highlightMoveDuration: 300

    preferredHighlightBegin: 0
    preferredHighlightEnd: 0
    highlightRangeMode: ListView.StrictlyEnforceRange
    highlightFollowsCurrentItem: true

    cacheBuffer: control.width * control.count
    boundsBehavior: Flickable.DragOverBounds
    currentIndex: -1
    clip: true

    signal clicked()

    NumberAnimation on contentX {
        id: scrollAnim

        duration: 300
        easing.type: Easing.InOutQuad

        onStopped: {
            var index = control.indexAt(control.contentX + control.width / 2,
                                        control.contentY + control.height / 2)
            if (index === -1)
                control.currentIndex = 0
            else
                control.currentIndex = index
        }
    }

    MouseArea {
        anchors.fill: parent
        //hoverEnabled: true
        //propagateComposedEvents: true
        //preventStealing: true
        z: -1

        onClicked: {
            //console.log("ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ")
            control.clicked()
        }

        onWheel: (wheel)=> {
            console.log("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWw")
            if (wheel.angleDelta.y > 0){
                scrollPreviousPage()
            } else {
                scrollNextPage()
            }
        }
    }

    Component.onCompleted: {
        dbg()
    }

    // Timer {
    //     interval: 5000; running: true; repeat: true
    //     onTriggered:{
    //         dbg()
    //     }
    // }


    function dbg(){
        console.log("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
                console.log("control.width = " + control.width)
                console.log("control.height = " + control.height)
        console.log("control.model = " + control.model)
        console.log("iconSize = " + control.iconSize)
        console.log("cellWidth = " + control.cellWidth)
        console.log("cellHeight = " + control.iconSize)
        console.log("rows = " + control.rows)
                console.log("columns = " + control.columns)
                console.log("pageCount = " + control.pageCount)
    }


     delegate: GridView {
         id: _page

         width: control.width
         height: control.height

         readonly property int pageIndex: index

         cellHeight: control.cellHeight
         cellWidth: control.cellWidth

         interactive: false

         moveDisplaced: Transition {
             NumberAnimation {
                 properties: "x, y"
                 duration: 300
                 easing.type: Easing.InOutQuad
             }
         }

         model: PageModel {
             id: _pageModel
             sourceModel: launcherModel
             startIndex: control.pageCount * _page.pageIndex
             limitCount: control.pageCount
         }

         delegate: GridItemDelegate {
             searchMode: control.searchMode
             pageIndex: _page.pageIndex
             pageCount: control.pageCount
             width: control.cellWidth
             height: control.cellHeight
         }



     }

    function calcExtraSpacing(cellSize, containerSize) {
        var availableColumns = Math.floor(containerSize / cellSize)
        var extraSpacing = 0
        if (availableColumns > 0) {
            var allColumnSize = availableColumns * cellSize
            var extraSpace = Math.max(containerSize - allColumnSize, 0)
            extraSpacing = extraSpace / availableColumns
        }
        return Math.floor(extraSpacing)
    }

    function scrollNextPage() {
        if (scrollAnim.running)
            return

        if (currentIndex < count - 1) {
            scrollAnim.to = control.currentItem.x + control.width
            scrollAnim.restart()
        }
    }

    function scrollPreviousPage() {
        if (scrollAnim.running)
            return

        if (currentIndex > 0) {
            scrollAnim.to = control.currentItem.x - control.width
            scrollAnim.restart()
        }
    }

}
