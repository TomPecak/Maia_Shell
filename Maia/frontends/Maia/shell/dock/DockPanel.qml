import QtQuick

import Maia.Backend as Maia

// Panel opened from a dock button. It has to be a child of the button: it opens
// towards the screen center, depending on the edge the dock is attached to,
// and "grows" out of the button.
Rectangle {
    id: panel

    // --- Public API ---

    property bool open: false
    // Edge the dock is attached to: Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge or Qt.RightEdge
    property int edge: Qt.TopEdge
    // Distance between the button and the panel
    property real spacing: 12

    // --- Appearance ---

    width: 300
    height: 300
    radius: 8
    color: "#E8000000"

    opacity: 0
    visible: opacity > 0

    // --- Geometry, relative to the button (parent) ---

    x: edge === Qt.LeftEdge ? parent.width + spacing
     : edge === Qt.RightEdge ? -width - spacing
     : 0
    y: edge === Qt.TopEdge ? parent.height + spacing
     : edge === Qt.BottomEdge ? -height - spacing
     : 0

    // Clicks inside the panel are handled here, they must not reach the items below
    // (e.g. the window-wide area which closes the panel)
    MouseArea {
        anchors.fill: parent
    }

    // The panel area receives input while the panel is visible
    Maia.MaskArea {
        anchors.fill: parent
    }

    // --- Open / close animation ---

    transform: [
        // The origin lies on the panel side facing the button, at the button center
        Scale {
            id: panelScale
            origin.x: panel.edge === Qt.LeftEdge ? 0
                    : panel.edge === Qt.RightEdge ? panel.width
                    : panel.parent ? panel.parent.width / 2 : 0
            origin.y: panel.edge === Qt.TopEdge ? 0
                    : panel.edge === Qt.BottomEdge ? panel.height
                    : panel.parent ? panel.parent.height / 2 : 0
            xScale: 0.8
            yScale: 0.8
        },
        // When closed the panel is shifted slightly towards the button
        Translate {
            id: panelShift
            x: panel.edge === Qt.LeftEdge ? -10 : panel.edge === Qt.RightEdge ? 10 : 0
            y: panel.edge === Qt.TopEdge ? -10 : panel.edge === Qt.BottomEdge ? 10 : 0
        }
    ]

    states: State {
        name: "open"
        when: panel.open
        PropertyChanges { target: panel; opacity: 1 }
        PropertyChanges { target: panelScale; xScale: 1; yScale: 1 }
        PropertyChanges { target: panelShift; x: 0; y: 0 }
    }

    transitions: [
        Transition {
            to: "open"
            NumberAnimation { target: panel; property: "opacity"; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation {
                targets: [panelScale, panelShift]
                properties: "xScale,yScale,x,y"
                duration: 280
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        },
        Transition {
            from: "open"
            NumberAnimation {
                targets: [panel, panelScale, panelShift]
                properties: "opacity,xScale,yScale,x,y"
                duration: 120
                easing.type: Easing.InCubic
            }
        }
    ]
}
