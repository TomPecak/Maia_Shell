import QtQuick

Item{

    property url  leftTopSource
    property url  leftMiddleSource
    property url leftBottomSource

    property url middleTopSource
    property url middleMiddleSource
    property url middleBottomSource

    property url rightTopSource
    property url rightMiddleSource
    property url rightBottomSource

    readonly property int leftColumnHeight: leftTop.sourceSize.height + leftMiddle.sourceSize.height + leftBottom.sourceSize.height
    readonly property int middleColumnHeight: middleTop.sourceSize.height + middleMiddle.sourceSize.height + middleBottom.sourceSize.height
    readonly property int rightColumnHeight: rightTop.sourceSize.height + rightMiddle.sourceSize.height + rightBottom.sourceSize.height

    readonly property int topRowWidth: leftTop.sourceSize.width + middleTop.sourceSize.width + rightTop.sourceSize.width
    readonly property int middleRowWidth: leftMiddle.sourceSize.width + middleMiddle.sourceSize.width + rightMiddle.sourceSize.width
    readonly property int bottomRowWidth: leftBottom.sourceSize.width + middleBottom.sourceSize.width + rightBottom.sourceSize.width

    property int minimumWidth: Math.max(topRowWidth, middleRowWidth, bottomRowWidth)
    property int minimumHeight: Math.max(leftColumnHeight, middleColumnHeight, rightColumnHeight)


    onHeightChanged: {
        if(height < minimumHeight){
            height = minimumHeight
        }
    }

    onWidthChanged: {
        if(width < minimumWidth){
            width = minimumWidth
        }
    }

    Image{
        id: leftTop
        anchors.top: parent.top
        anchors.left: parent.left
        width: sourceSize.width
        height: sourceSize.height
        source: parent.leftTopSource
    }

    Image{
        id: leftMiddle
        anchors.top: leftTop.bottom
        anchors.left: parent.left
        anchors.bottom: leftBottom.top
        fillMode: Image.TileVertically
        source: parent.leftMiddleSource
    }

    Image{
        id: leftBottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: sourceSize.width
        height: sourceSize.height
        source: parent.leftBottomSource
    }

    Image{
        id: rightTop
        anchors.top: parent.top
        anchors.right: parent.right
        width: sourceSize.width
        height: sourceSize.height
        source: parent.rightTopSource
    }

    Image{
        id: rightMiddle
        anchors.top: rightTop.bottom
        anchors.right: parent.right
        anchors.bottom:rightBottom.top
        fillMode: Image.TileVertically
        source: parent.rightMiddleSource
    }

    Image{
        id: rightBottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: sourceSize.width
        height: sourceSize.height
        source: parent.rightBottomSource
    }

    Image{
        id: middleBottom
        anchors.bottom: parent.bottom
        anchors.left: leftBottom.right
        anchors.right: rightBottom.left
        fillMode: Image.TileHorizontally
        source: parent.middleBottomSource
    }

    Image{
        id: middleTop
        anchors.top: parent.top
        anchors.left: leftMiddle.right
        anchors.right: rightMiddle.left
        fillMode: Image.TileHorizontally
        source: parent.middleTopSource
    }

    Image{
        id: middleMiddle
        anchors.top: middleTop.bottom
        anchors.left: leftMiddle.right
        anchors.right: rightMiddle.left
        anchors.bottom: middleBottom.top
        source: parent.middleMiddleSource
    }
}
