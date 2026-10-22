import QtQuick
import QtQuick.Controls
import QtCore

// Stack of sticky notes on the desktop; the top one is editable and its text is persisted

Rectangle{
    id: baseNote
    height: 260
    width: 260

     visible: true

            color: "#66cded"

    transformOrigin: Item.BottomRight
    rotation: 6*diff

    property int diff: 3

    // layer.enabled: true

    // layer.effect: MultiEffect {

    //     autoPaddingEnabled: true
    //     shadowEnabled: true
    //     shadowBlur: 0.4
    //     shadowHorizontalOffset: 2.4
    //     shadowOpacity: 0.5
    //     shadowScale: 1.0
    //     shadowVerticalOffset: 2.4
    //     visible: true //don't work in layer
    //     opacity: 1.0 //don't work in layer
    // }

    Rectangle{
        height: 260
        width: 260

        anchors.bottom: parent.bottom

                color: "#daf2f4"

        transformOrigin: Item.BottomRight
        rotation: -baseNote.diff

        Rectangle{
            height: 260
            width: 260

            anchors.bottom: parent.bottom

                    color: "#ffafea"

            transformOrigin: Item.BottomRight
            rotation: -baseNote.diff

            Rectangle{
                height: 260
                width: 260

                anchors.bottom: parent.bottom

                        color: "#fff890"

                transformOrigin: Item.BottomRight
                rotation: -baseNote.diff

            }

            Rectangle{
                height: 260
                width: 260

                anchors.bottom: parent.bottom

                        color: "#fff890"

                transformOrigin: Item.BottomRight
                rotation: -baseNote.diff

                Rectangle{
                    height: 260
                    width: 260

                    anchors.bottom: parent.bottom

                            color: "#d8b8ff"

                    transformOrigin: Item.BottomRight
                    rotation: -baseNote.diff

                    Rectangle{
                        height: 260
                        width: 260

                        anchors.bottom: parent.bottom

                                color: "#f6f0e2"

                        transformOrigin: Item.BottomRight
                        rotation: -baseNote.diff

                        Rectangle{
                            height: 260
                            width: 260

                            anchors.bottom: parent.bottom

                                    color: "#96ebd6"

                            transformOrigin: Item.BottomRight
                            rotation: -baseNote.diff

                            TextArea{
                                id: noteTxt
                                anchors.fill: parent
                                anchors.margins: 10

                                placeholderText: qsTr("New note...")
                                wrapMode: Text.WordWrap
                                font.family: "NeverMind Handwriting"
                                font.pointSize: 12
                                color: "#000099"

                                Settings {
                                    property alias noteText: noteTxt.text
                                }

                            }

                        }

                    }
                }

            }

        }

    }

}

// MultiEffect {
//     source: baseNote
//     anchors.fill: baseNote

//     transformOrigin: Item.BottomRight
//     rotation: 6*3

// autoPaddingEnabled: true
// shadowEnabled: true
// shadowBlur: 0.4
// shadowHorizontalOffset: 2.4
// shadowOpacity: 0.5
// shadowScale: 1.0
// shadowVerticalOffset: 2.4
// visible: true //don't work in layer
// opacity: 1.0 //don't work in layer
// }
