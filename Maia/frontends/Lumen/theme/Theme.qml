pragma Singleton

import QtQuick
import QtCore

// Design tokens of the Lumen frontend: colors, typography, spacing, shapes and motion.
// Every component takes its look from here, so the light / dark mode and the accent
// color can be switched at runtime.
QtObject {
    id: theme

    // --- Personalization (persisted) ---

    readonly property bool dark: settings.dark
    readonly property int accentIndex: Math.max(0, Math.min(accents.length - 1, settings.accentIndex))
    // Apply the theme colors to applications (KDE color scheme), see services/AppColorSync.qml.
    // Off by default: it changes the colors of all applications of the user.
    readonly property bool appColors: settings.appColors

    function setDark(value) {
        settings.dark = value
    }

    function setAccentIndex(index) {
        settings.accentIndex = index
    }

    function setAppColors(value) {
        settings.appColors = value
    }

    property Settings settings: Settings {
        category: "LumenFrontend"

        property bool dark: true
        property int accentIndex: 0
        property bool appColors: false
    }

    // Accent palettes: a darker tone for the light mode and a lighter one for the dark mode,
    // so the accent always has enough contrast against the surfaces
    readonly property var accents: [
        { name: qsTr("Azure"),   light: "#005FB8", dark: "#60CDFF" },
        { name: qsTr("Violet"),  light: "#6B4FE0", dark: "#B9A8FF" },
        { name: qsTr("Teal"),    light: "#00796B", dark: "#4FD8C4" },
        { name: qsTr("Emerald"), light: "#107C10", dark: "#7DD87D" },
        { name: qsTr("Amber"),   light: "#B35C00", dark: "#FFB95C" },
        { name: qsTr("Rose"),    light: "#BF2D73", dark: "#FF9ACB" }
    ]

    // --- Colors ---

    readonly property color accent: dark ? accents[accentIndex].dark : accents[accentIndex].light
    readonly property color accentHover: dark ? Qt.darker(accent, 1.12) : Qt.lighter(accent, 1.15)
    readonly property color accentPressed: dark ? Qt.darker(accent, 1.25) : Qt.lighter(accent, 1.3)
    // Text and icons placed on the accent color
    readonly property color onAccent: dark ? "#000000" : "#FFFFFF"

    readonly property color textPrimary: dark ? "#FFFFFF" : "#1A1A1A"
    readonly property color textSecondary: dark ? "#C9C9C9" : "#5C5C5C"
    readonly property color textTertiary: dark ? "#9B9B9B" : "#8A8A8A"

    // Taskbar and flyouts: translucent "acrylic" surfaces
    readonly property color taskbar: dark ? Qt.rgba(0.10, 0.10, 0.11, 0.86) : Qt.rgba(0.95, 0.95, 0.96, 0.86)
    readonly property color surface: dark ? Qt.rgba(0.15, 0.15, 0.16, 0.975) : Qt.rgba(0.97, 0.97, 0.98, 0.975)
    // Cards placed on surfaces
    readonly property color card: dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.75)
    // Controls (text fields, tiles in the off state, slider tracks)
    readonly property color control: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.85)
    readonly property color controlStrong: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14)
    // Hover and pressed overlays of transparent (subtle) controls
    readonly property color subtleHover: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.045)
    readonly property color subtlePressed: dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.025)
    // Borders and dividers
    readonly property color stroke: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color divider: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.18)

    // Application windows (File Explorer): the frame with the tabs ("mica", slightly tinted
    // by the accent), the active tab and the toolbars, the content area
    readonly property color windowChrome: Qt.tint(dark ? "#1b1b1e" : "#e7ebf1",
                                                  Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.05 : 0.07))
    readonly property color windowToolbar: dark ? "#2a2a2e" : "#f9fafb"
    readonly property color windowContent: dark ? "#232326" : "#ffffff"
    // Selected items in lists and grids
    readonly property color selection: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.24 : 0.16)
    readonly property color selectionHover: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.32 : 0.22)
    // Close button of a window
    readonly property color closeHover: "#c42b1c"
    readonly property color closePressed: "#a3271b"

    // Wallpaper base gradient, the accent is blended into it by the wallpaper
    readonly property color wallpaperTop: dark ? "#0A0E1E" : "#E3ECF7"
    readonly property color wallpaperBottom: dark ? "#16112B" : "#F5F0FA"

    // --- Typography ---

    readonly property string fontFamily: Qt.application.font.family
    readonly property int fontCaption: 12
    readonly property int fontBody: 14
    readonly property int fontBodyLarge: 16
    readonly property int fontSubtitle: 20
    readonly property int fontTitle: 28
    readonly property int fontDisplay: 56

    // --- Spacing and shapes ---

    readonly property int spacingXS: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 16
    readonly property int spacingXL: 24

    readonly property int radiusSmall: 4    // buttons, text fields, tiles
    readonly property int radiusMedium: 8   // cards, flyouts
    readonly property int radiusLarge: 12   // large surfaces

    readonly property int taskbarHeight: 48

    // --- Motion ---

    readonly property int durationFast: 120
    readonly property int durationNormal: 220
    readonly property int durationSlow: 360
    // Entering elements decelerate, leaving elements accelerate
    readonly property int easingEnter: Easing.OutCubic
    readonly property int easingExit: Easing.InCubic
    readonly property int easingStandard: Easing.InOutCubic
    // Distance an entering flyout travels
    readonly property int flyoutOffset: 32

    // --- Icons ---

    // Icon from the icon theme (Breeze) through the image provider of the Maia backend
    function iconUrl(name) {
        return "image://icontheme/" + name
    }
}
