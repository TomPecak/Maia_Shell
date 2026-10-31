import QtQuick
import QtCore

// Where the dock rests, kept between sessions.
//
// The only place that knows how the state is stored, so the storage can change without touching
// the dock: today QtCore Settings (the [MaiaDock] group of ~/.config/Maia/Maia_<version>.conf,
// like Lumen's settings), later the settings service (TODO.md). The edge is stored by name, not
// as the number of Qt.Edge; an unknown or missing name means the top edge.
QtObject {
    id: state

    // Edge the dock rests at: Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge or Qt.RightEdge
    readonly property int edge: edges[settings.edge] ?? Qt.TopEdge

    function setEdge(edge) {
        const name = Object.keys(edges).find(key => edges[key] === edge)
        if (name !== undefined)
            settings.edge = name
    }

    readonly property var edges: ({
        top: Qt.TopEdge,
        bottom: Qt.BottomEdge,
        left: Qt.LeftEdge,
        right: Qt.RightEdge
    })

    property Settings settings: Settings {
        category: "MaiaDock"

        property string edge: "top"
    }
}
