import QtQuick
import QtQuick.Layouts

import Maia.Backend as Maia

// Draggable dock which snaps to the nearest screen edge when it is released.
//
// The dock has to be placed directly in a full-screen item (normally the window
// content item), its parent defines the area in which the dock can be moved.
// Window-wide input handling (closing the panel by clicking outside of it and
// capturing the pointer while dragging) belongs to the window, see LayerTop.qml.
Rectangle {
    id: dock

    // --- Public API ---

    // Size across the edge the dock is attached to
    property real shortSize: 80
    // Distance between the dock border and its buttons, and between the buttons
    property real padding: 10
    property real spacing: 10
    // Size of the (square) buttons
    readonly property real buttonSize: shortSize - 2 * padding
    // Size along the edge, follows the number of buttons
    property real longSize: (vertical ? buttonsLayout.implicitHeight : buttonsLayout.implicitWidth)
                            + 2 * padding
    // Distance from the screen edge
    property real edgeMargin: 15
    // Edge the dock is attached to: Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge or Qt.RightEdge
    property int edge: Qt.TopEdge
    // Whether the launcher panel is open
    property bool panelOpen: false

    readonly property bool vertical: edge === Qt.LeftEdge || edge === Qt.RightEdge
    readonly property bool dragging: d.dragging

    // Final size for the current edge (width/height are animated towards it)
    readonly property real targetWidth: vertical ? shortSize : longSize
    readonly property real targetHeight: vertical ? longSize : shortSize

    // --- Appearance ---

    radius: 25
    color: "#55000000"

    // "Pressed" effect while the dock is grabbed
    scale: dragArea.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

    // --- Geometry ---

    width: targetWidth
    height: targetHeight

    // While dragging the dock follows the pointer, holding the point it was grabbed by,
    // otherwise it is attached to its edge
    x: {
        if (!parent)
            return 0
        if (d.dragging)
            return d.pointer.x - targetWidth * d.grabRatioX
        if (edge === Qt.LeftEdge)
            return edgeMargin
        if (edge === Qt.RightEdge)
            return parent.width - targetWidth - edgeMargin
        return (parent.width - targetWidth) / 2
    }

    y: {
        if (!parent)
            return 0
        if (d.dragging)
            return d.pointer.y - targetHeight * d.grabRatioY
        if (edge === Qt.TopEdge)
            return edgeMargin
        if (edge === Qt.BottomEdge)
            return parent.height - targetHeight - edgeMargin
        return (parent.height - targetHeight) / 2
    }

    // While dragging the position follows the pointer quickly, after release the dock
    // slowly snaps to its edge. The size always changes slowly.
    Behavior on x { NumberAnimation { duration: d.moveDuration; easing.type: Easing.OutQuart } }
    Behavior on y { NumberAnimation { duration: d.moveDuration; easing.type: Easing.OutQuart } }
    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
    Behavior on height { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }

    // Grabs the dock, it is declared first so that the dock content lies above it
    MouseArea {
        id: dragArea

        anchors.fill: parent
        preventStealing: true

        onPressed: function (mouse) {
            d.beginDrag(mouse.x / dock.width, mouse.y / dock.height,
                        mapToItem(dock.parent, mouse.x, mouse.y))
        }
        onPositionChanged: function (mouse) {
            d.updatePointer(mapToItem(dock.parent, mouse.x, mouse.y))
        }
        onReleased: d.endDrag()
        onCanceled: d.endDrag()
    }

    // The dock area receives input, the rest of the window lets it through
    Maia.MaskArea {
        anchors.fill: parent
    }

    // Buttons in a row (horizontal dock) or in a column (vertical dock)
    GridLayout {
        id: buttonsLayout

        anchors.centerIn: parent
        flow: dock.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: dock.spacing
        columnSpacing: dock.spacing

        Repeater {
            model: d.applications

            delegate: DockButton {
                required property var modelData

                Layout.preferredWidth: dock.buttonSize
                Layout.preferredHeight: dock.buttonSize
                iconName: modelData.iconName

                onClicked: dock.launchApplication(modelData.command)
            }
        }

        DockSeparator {
            Layout.preferredWidth: dock.vertical ? dock.buttonSize : 1
            Layout.preferredHeight: dock.vertical ? 1 : dock.buttonSize
        }

        // Opens the dock panel
        DockButton {
            id: panelButton

            Layout.preferredWidth: dock.buttonSize
            Layout.preferredHeight: dock.buttonSize
            iconSource: Qt.resolvedUrl("../assets/pngegg.png")

            background: Rectangle {
                color: "white"
                radius: 10
            }

            onClicked: dock.panelOpen = !dock.panelOpen

            DockPanel {
                open: dock.panelOpen
                edge: dock.edge
            }
        }
    }

    // TODO: Starting applications is not implemented yet (in the Quickshell dock it was done
    // with Quickshell.Io.Process), it should be done by the Maia backend.
    function launchApplication(command) {
        console.log("[Dock] launchApplication() not implemented, command:", JSON.stringify(command))
    }

    // --- Private state ---

    QtObject {
        id: d

        // Applications in the dock, taken from the Quickshell dock
        readonly property var applications: [
            { iconName: "camera-photo",
              command: ["sh", "-c", "(PLIK=~/Obrazy/Screenshots/$(date +%F_%H-%M-%S).png && grim -g \"$(slurp)\" \"$PLIK\" && nautilus -s \"$PLIK\") &"] },
            { iconName: "org.gnome.Calculator", command: ["gnome-calculator"] },
            { iconName: "vscode", command: ["sh", "-c", "code &"] },
            { iconName: "org.gnome.Terminal", command: ["sh", "-c", "gnome-terminal &"] },
            { iconName: "qterminal", command: ["qterminal", "&"] },
            { iconName: "google-chrome", command: ["sh", "-c", "google-chrome &"] },
            { iconName: "org.gnome.Nautilus", command: ["sh", "-c", "nautilus &"] },
            { iconName: "designer-qt5", command: ["sh", "-c", "/home/rafal/Qt/Qt_6_11_1/Tools/QtCreator/bin/qtcreator"] },
            { iconName: "org.gnome.SystemMonitor", command: ["sh", "-c", "gnome-system-monitor &"] },
            { iconName: "org.gnome.Settings", command: ["env", "XDG_CURRENT_DESKTOP=GNOME", "gnome-control-center"] },
            { iconName: "org.gnome.gedit", command: ["sh", "-c", "gnome-text-editor /home/rafal/.config/quickshell/* &"] }
        ]

        property bool dragging: false
        // Position animation duration, changed before 'dragging' so the release
        // animation always starts with the slow duration
        property int moveDuration: 450
        // Point the dock was grabbed by, relative to its size (0..1)
        property real grabRatioX: 0.5
        property real grabRatioY: 0.5
        // Pointer position in parent coordinates
        property point pointer: Qt.point(0, 0)

        function beginDrag(ratioX, ratioY, position) {
            grabRatioX = ratioX
            grabRatioY = ratioY
            moveDuration = 50
            updatePointer(position)
            dragging = true
        }

        function endDrag() {
            if (!dragging)
                return
            moveDuration = 450
            dragging = false
        }

        function updatePointer(position) {
            const area = dock.parent
            const px = Math.max(0, Math.min(area.width, position.x))
            const py = Math.max(0, Math.min(area.height, position.y))
            pointer = Qt.point(px, py)

            // Pointer position relative to the screen center (-1..1); the screen is divided
            // into four zones by its diagonals, each zone belongs to one edge
            const nx = (px / area.width) * 2 - 1
            const ny = (py / area.height) * 2 - 1
            if (Math.abs(nx) > Math.abs(ny))
                dock.edge = nx > 0 ? Qt.RightEdge : Qt.LeftEdge
            else
                dock.edge = ny > 0 ? Qt.BottomEdge : Qt.TopEdge
        }
    }
}
