import QtQuick
import QtQuick.Shapes

import ".."

// Generated wallpaper: a soft vertical gradient with large blurred "blooms" of light in tones
// of the accent color. It follows the light / dark mode and the accent with a cross-fade.
// It is static (no running animations), so it does not cost anything after it is drawn.
Item {
    id: wallpaper

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.wallpaperTop; Behavior on color { ColorAnimation { duration: Theme.durationSlow } } }
            GradientStop { position: 1.0; color: Theme.wallpaperBottom; Behavior on color { ColorAnimation { duration: Theme.durationSlow } } }
        }
    }

    // Large soft light spot drawn with a radial gradient fading to transparent
    component Bloom: Shape {
        id: bloom

        property color tint: Theme.accent
        property real strength: 0.55

        Behavior on tint { ColorAnimation { duration: Theme.durationSlow } }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: bloom.width / 2; centerY: bloom.height / 2
                centerRadius: bloom.width / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Qt.alpha(bloom.tint, bloom.strength) }
                GradientStop { position: 0.55; color: Qt.alpha(bloom.tint, bloom.strength * 0.35) }
                GradientStop { position: 1.0; color: Qt.alpha(bloom.tint, 0) }
            }

            PathRectangle { width: bloom.width; height: bloom.height }
        }
    }

    Bloom {
        x: wallpaper.width * 0.45
        y: -wallpaper.height * 0.35
        width: wallpaper.width * 0.9
        height: width
        tint: Theme.accent
        strength: Theme.dark ? 0.55 : 0.45
    }

    Bloom {
        x: -wallpaper.width * 0.25
        y: wallpaper.height * 0.35
        width: wallpaper.width * 0.8
        height: width
        // Second tone: the accent shifted towards violet / blue
        tint: Qt.hsla((Theme.accent.hslHue + 0.12) % 1, Theme.accent.hslSaturation, Theme.accent.hslLightness, 1)
        strength: Theme.dark ? 0.45 : 0.35
    }

    Bloom {
        x: wallpaper.width * 0.25
        y: wallpaper.height * 0.55
        width: wallpaper.width * 0.6
        height: width
        tint: Qt.hsla((Theme.accent.hslHue + 0.9) % 1, Theme.accent.hslSaturation, Theme.accent.hslLightness, 1)
        strength: Theme.dark ? 0.30 : 0.25
    }
}
