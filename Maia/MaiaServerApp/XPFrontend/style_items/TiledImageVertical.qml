import QtQuick

Item{
    property url topSource
    property url middleSource
    property url bottomSource

    readonly property int columnHeight: topImage.sourceSize.height + middleImage.sourceSize.height + bottomImage.sourceSize.height

    property int minimumWidth: Math.max(topImage.sourceSize.width, middleImage.sourceSize.width, bottomImage.sourceSize.width)
    property int minimumHeight: columnHeight


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
        id: topImage
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        fillMode: Image.Stretch
        source: parent.topSource
    }

    Image{
        id: middleImage
        anchors.top: topImage.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomImage.top
        fillMode: Image.TileVertically
        source: parent.middleSource
    }

    Image{
        id: bottomImage
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        fillMode: Image.Stretch
        source: parent.bottomSource
    }
}
