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
            height: 20
            border.color: "#EEEEEE"
            //color: getPastelColor(process_id)
            color: index === activeIndex ? Qt.lighter(getPastelColor(process_id), 1.3) : getPastelColor(process_id)

            Row {
                anchors.fill: parent
                Text {
                    text: process_id + " | " // message // First field
                }
                TextEdit {
                    text: message
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    activeIndex = index // Set active index on click
                }
                onPressed: {
                    //activeIndex = index // Set active index on drag start
                }
                onReleased: {
                    // Optional: can reset activeIndex on mouse release
                    // activeIndex = -1
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
