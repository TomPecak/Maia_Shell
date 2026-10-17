import QtQuick

import Maia.Backend as Maia

import ".."

// Keeps the colors of the applications (KDE color scheme) in sync with the Lumen theme.
//
// While Theme.appColors is enabled, every change of the light / dark mode or of the accent
// generates the "Lumen" KDE color scheme and applies it: Qt Widgets, Kirigami and QML
// applications with the KDE platform theme follow it, KWin uses it for window decorations.
// When it is disabled, the color scheme the user had before is restored.
QtObject {
    id: sync

    property Maia.MKdeColorScheme scheme: Maia.MKdeColorScheme {}

    // Changes are applied with a short delay, so quick switching writes the scheme only once
    property Timer applyTimer: Timer {
        interval: 400
        onTriggered: sync.update()
    }

    readonly property var watchedState: [Theme.dark, Theme.accentIndex, Theme.appColors]
    onWatchedStateChanged: applyTimer.restart()

    Component.onCompleted: applyTimer.restart()

    function update() {
        if (Theme.appColors)
            scheme.apply("MaiaLumen", "Lumen (Maia Shell)", colorGroups())
        else
            scheme.restorePrevious() // does nothing if the Lumen scheme was not applied
    }

    // KDE color scheme generated from the theme tokens. KDE colors are opaque, so the
    // translucent surfaces of the shell are replaced by their solid counterparts.
    function colorGroups() {
        const dark = Theme.dark
        const accent = Theme.accent
        const onAccent = Theme.onAccent

        const p = dark ? {
            window: "#202020", windowAlt: "#272727",
            view: "#1C1C1C", viewAlt: "#242424",
            button: "#2D2D2D", buttonAlt: "#333333",
            header: "#202020", headerAlt: "#272727",
            tooltip: "#2B2B2B",
            text: "#FFFFFF", textInactive: "#A0A0A0",
            negative: "#FF99A4", neutral: "#FCE100", positive: "#6CCB5F"
        } : {
            window: "#F3F3F3", windowAlt: "#EBEBEB",
            view: "#FFFFFF", viewAlt: "#F7F7F7",
            button: "#FBFBFB", buttonAlt: "#F3F3F3",
            header: "#EEEEEE", headerAlt: "#E6E6E6",
            tooltip: "#F9F9F9",
            text: "#1A1A1A", textInactive: "#5C5C5C",
            negative: "#C42B1C", neutral: "#9D5D00", positive: "#0F7B0F"
        }

        const visited = dark ? Qt.lighter(accent, 1.25) : Qt.darker(accent, 1.25)

        function colorSet(background, backgroundAlternate, foreground, inactive) {
            return {
                BackgroundNormal: Qt.color(background),
                BackgroundAlternate: Qt.color(backgroundAlternate),
                ForegroundNormal: Qt.color(foreground),
                ForegroundInactive: Qt.color(inactive),
                ForegroundActive: accent,
                ForegroundLink: accent,
                ForegroundVisited: visited,
                ForegroundNegative: Qt.color(p.negative),
                ForegroundNeutral: Qt.color(p.neutral),
                ForegroundPositive: Qt.color(p.positive),
                DecorationFocus: accent,
                DecorationHover: accent
            }
        }

        // Selected items: accent background with the text color for the accent
        const selection = colorSet(accent, Qt.darker(accent, 1.1), onAccent, onAccent)
        selection.ForegroundActive = onAccent
        selection.ForegroundLink = onAccent
        selection.ForegroundVisited = onAccent

        return {
            "Colors:Window": colorSet(p.window, p.windowAlt, p.text, p.textInactive),
            "Colors:View": colorSet(p.view, p.viewAlt, p.text, p.textInactive),
            "Colors:Button": colorSet(p.button, p.buttonAlt, p.text, p.textInactive),
            "Colors:Header": colorSet(p.header, p.headerAlt, p.text, p.textInactive),
            "Colors:Tooltip": colorSet(p.tooltip, p.window, p.text, p.textInactive),
            // Complementary areas (e.g. OSDs) are dark in both modes, as in Breeze
            "Colors:Complementary": colorSet("#202020", "#272727", "#FFFFFF", "#A0A0A0"),
            "Colors:Selection": selection,
            // Window decorations of KWin
            "WM": {
                activeBackground: Qt.color(p.header),
                activeForeground: Qt.color(p.text),
                activeBlend: Qt.color(p.text),
                inactiveBackground: Qt.color(p.header),
                inactiveForeground: Qt.color(p.textInactive),
                inactiveBlend: Qt.color(p.textInactive)
            },
            // Disabled and inactive effects, the same as in the Breeze schemes
            "ColorEffects:Disabled": {
                Color: Qt.color("#383838"), ColorAmount: 0, ColorEffect: 0,
                ContrastAmount: 0.65, ContrastEffect: 1, IntensityAmount: 0.1, IntensityEffect: 2
            },
            "ColorEffects:Inactive": {
                ChangeSelectionColor: true, Color: Qt.color("#706F6E"), ColorAmount: 0.025, ColorEffect: 2,
                ContrastAmount: 0.1, ContrastEffect: 2, Enable: false, IntensityAmount: 0, IntensityEffect: 0
            }
        }
    }
}
