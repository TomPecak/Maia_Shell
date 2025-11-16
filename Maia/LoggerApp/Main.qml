import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    width: 640
    height: 480
    visible: true
    title: qsTr("Logger")

    property var colorMap: ({})
    property int activeIndex: -1

    function generatePastelColor() {
        // Generates a random RGB color with high brightness and low saturation
        var r = Math.floor(Math.random() * 46 + 210); // 200-255 for light shades
        var g = Math.floor(Math.random() * 46 + 210);
        var b = Math.floor(Math.random() * 46 + 210);
        return Qt.rgba(r / 255, g / 255, b / 255, 1);
    }

    function getPastelColor(processId) {
        // Check if a color for process_id already exists
        if (colorMap.hasOwnProperty(processId)) {
            return colorMap[processId];
        }

        // Store the color in the map
        var color = generatePastelColor();
        colorMap[processId] = color;
        return color;
    }

    RowLayout {
        id: menu
        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 7

        CheckBox {
            id: autoScroll
            text: "Autoscroll"
            checked: true
        }
        Button {
            text: "Clear log"
            onClicked: {
                backend.clearCurrentLogModel()
            }
        }
        ComboBox {
            id: portComboBox
            model: [50000, 50001, 50002, 50003, 50004, 50005, 50006, 50007, 50008, 50009]
            currentIndex: backend.port
            displayText: "Port: " + backend.port
            onActivated: {
                backend.port = model[index]
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }

    ListView {
        id: logListView
        anchors.top: menu.bottom
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: serverComboBox.top

        model: backend.logModel
        flickDeceleration: 0.01

        ScrollBar.vertical: ScrollBar {
            id: verticalScrollBar
            active: true
            policy: ScrollBar.AlwaysOn
            width: 12
        }

        delegate: Rectangle {
            width: logListView.width
            // Usuń stałą wysokość!
            // height: 20 → ZAMIENIĆ NA:
            height: row.implicitHeight + 8  // + padding

            border.color: "#EEEEEE"
            color: index === activeIndex ? Qt.lighter(getPastelColor(process_id), 1.3) : getPastelColor(process_id)

            Row {
                id: row
                anchors.fill: parent
                anchors.margins: 4
                spacing: 8

                Text {
                    text: process_id + " | "
                    verticalAlignment: Text.AlignTop
                    font.pointSize: 10
                }

                Text {
                    text: message
                    width: parent.width - parent.spacing - parent.children[0].width
                    wrapMode: Text.WrapAnywhere
                    font.pointSize: 10
                    verticalAlignment: Text.AlignTop
                    // Opcjonalnie: elide jeśli nie chcesz zawijania (ale wtedy nie widać całości)
                    // elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    activeIndex = index
                }
            }
        }
        onCountChanged: {
            // Set currentIndex to the last element
            if(autoScroll.checked) {
                currentIndex = count - 1
            }
        }
    }

    ComboBox {
        id: serverComboBox
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        model: backend.serverAddresses  // Directly use the list as the model
        currentIndex: 0  // Default to the first address
        // Optional: onActivated: { console.log("Selected: " + model[index]) } // If you want to do something with the selection
        // displayText: "Server: " + currentText  // If you want to show only the selected item
    }
}
