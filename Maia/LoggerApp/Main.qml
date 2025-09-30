import QtQuick
import QtQuick.Controls

Window {
    width: 640
    height: 480
    visible: true
    title: qsTr("Logger")

    property var colorMap: ({})
    property int activeIndex: -1

    function generatePastelColor() {
        // Generuje losowy kolor w formacie RGB z wysokimi wartościami jasności i niskim nasyceniem
        var r = Math.floor(Math.random() * 46 + 210); // 200-255 dla jasnych odcieni
        var g = Math.floor(Math.random() * 46 + 210);
        var b = Math.floor(Math.random() * 46 + 210);
        return Qt.rgba(r / 255, g / 255, b / 255, 1);
    }

    function getPastelColor(processId) {
        // Sprawdź, czy kolor dla process_id już istnieje
        if (colorMap.hasOwnProperty(processId)) {
            return colorMap[processId];
        }

        // Zapisz kolor w mapie
        var color = generatePastelColor();
        colorMap[processId] = color;
        return color;
    }

    Row{
        id: menu
        z: 1
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        CheckBox{
            id: autoScroll
            text: "Autoscroll"
            checked: true
        }
        Button{
            text: "Clear log"
            onClicked: {
                backend.clearCurrentLogModel()
            }
        }

        ComboBox {
            id: channelComboBox
            model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
            currentIndex: backend.channel // Synchronizacja z backend.channel
            displayText: "Channel: " + backend.channel
            onActivated: {
                backend.channel = currentIndex // Zmiana kanału w backendzie
            }
        }
    }

    ListView {
        id: logListView
        anchors.top: menu.bottom
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.bottom: parent.bottom

        model: backend.logModel
        flickDeceleration: 0.01

        ScrollBar.vertical: ScrollBar {
                    id: verticalScrollBar
                    active: true // Pasek widoczny podczas przewijania
                    policy: ScrollBar.AlwaysOn // Pasek pojawia się, gdy zawartość jest większa niż widok
                    width: 12 // Szerokość paska przewijania
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
                    text: process_id + " | "// message // Pierwsze pole
                }
                TextEdit {
                    text: message
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    activeIndex = index // Ustaw aktywny indeks po kliknięciu
                }
                onPressed: {
                    //activeIndex = index // Ustaw aktywny indeks przy rozpoczęciu przeciągania
                }
                onReleased: {
                    // Opcjonalnie: można zresetować activeIndex po puszczeniu myszy
                    // activeIndex = -1
                }
            }
        }
        onCountChanged: {
            // Ustawienie currentIndex na ostatni element
            if(autoScroll.checked){
                currentIndex = count - 1
            }
        }


    }
}
