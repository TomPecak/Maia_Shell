pragma Singleton

import QtQuick
import QtCore

// Colors of the Maia frontend: the semantic colors of iPadOS 18 (UIKit: label, fills, grouped
// backgrounds, separator, system colors) in a light and a dark variant. Opaque surfaces only, no
// blur: a layer-shell surface cannot see the windows below it.
//
// The mode is kept between sessions (the [MaiaAppearance] group of ~/.config/Maia/Maia_<version>.conf).
// Each layer of the frontend is its own process with its own copy of this singleton: a change made
// in one layer reaches the others only at their next start (TODO.md, item 7).
QtObject {
    id: theme

    readonly property bool dark: settings.dark

    function setDark(value) {
        settings.dark = value
    }

    property Settings settings: Settings {
        category: "MaiaAppearance"

        property bool dark: false
    }

    // --- Text ---

    readonly property color label: dark ? "#ffffff" : "#000000"
    readonly property color secondaryLabel: dark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
                                                 : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.6)
    readonly property color tertiaryLabel: dark ? Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.3)
                                                : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.3)

    // --- Surfaces ---

    // Large surfaces lying over the desktop (the App Library): systemGroupedBackground, in the dark
    // the elevated variant, so the surface stands apart from a dark wallpaper
    readonly property color surface: dark ? "#1c1c1e" : "#f2f2f7"
    // Plates on a surface (icon plates in the dock, the thumb of a segmented control)
    readonly property color plate: dark ? "#2c2c2e" : "#ffffff"
    readonly property color segmentThumb: dark ? "#636366" : "#ffffff"
    // The dock: a light or dark material over the wallpaper, slightly translucent
    readonly property color dock: dark ? Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.86)
                                       : Qt.rgba(246 / 255, 246 / 255, 248 / 255, 0.82)
    // Hairline around surfaces lying on the wallpaper; the shadow sets them apart, the hairline
    // keeps the outline crisp on a wallpaper of the same brightness
    readonly property color hairline: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color separator: dark ? Qt.rgba(84 / 255, 84 / 255, 88 / 255, 0.6)
                                            : Qt.rgba(60 / 255, 60 / 255, 67 / 255, 0.29)
    // Dims the desktop below a modal surface
    readonly property color scrim: dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(0, 0, 0, 0.18)
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.5 : 0.22)

    // --- Fills (controls on a surface) ---

    // tertiarySystemFill: search field, segmented control track
    readonly property color fill: dark ? Qt.rgba(118 / 255, 118 / 255, 128 / 255, 0.24)
                                       : Qt.rgba(118 / 255, 118 / 255, 128 / 255, 0.12)
    // The pointer highlight of iPadOS (hover) and its pressed variant
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
    // Plates in the dock under the pointer
    readonly property color plateHover: dark ? "#3a3a3c" : "#f2f2f7"
    readonly property color platePressed: dark ? "#48484a" : "#e5e5ea"

    // --- System colors ---

    readonly property color accent: dark ? "#0a84ff" : "#007aff"
    readonly property color blue: dark ? "#0a84ff" : "#007aff"
    readonly property color green: dark ? "#30d158" : "#34c759"
    readonly property color orange: dark ? "#ff9f0a" : "#ff9500"
    readonly property color pink: dark ? "#ff375f" : "#ff2d55"
    readonly property color yellow: dark ? "#ffd60a" : "#ffcc00"

    // --- Motion ---

    // Color changes when the mode switches (crossfade of iPadOS)
    readonly property int modeChangeDuration: 250
}
