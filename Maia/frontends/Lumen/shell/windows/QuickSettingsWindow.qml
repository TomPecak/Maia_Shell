import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.layershell 1.0 as LayerShell

import LumenFrontend

// Quick settings, in the bottom-right corner above the system tray.
// Real: dark mode and accent color (persisted), volume (Maia audio backend).
// Mock-ups: network, bluetooth, airplane mode, night light, brightness, battery.
FlyoutWindow {
    id: quickSettings

    flyoutName: "quickSettings"
    cardWidth: 380
    // The card follows its content
    windowCardHeight: 640
    cardHeight: Math.min(windowCardHeight, layout.implicitHeight + 2 * Theme.spacingXL)
    edges: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight

    readonly property bool hasAudio: typeof audioBackend !== "undefined" && audioBackend !== null

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Theme.spacingXL
        spacing: Theme.spacingL

        // --- Toggles ---

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Theme.spacingM
            rowSpacing: Theme.spacingL

            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Wi-Fi")
                iconName: "network-wireless-signal-excellent-symbolic"
                checked: Shell.wifiEnabled
                onToggled: Shell.wifiEnabled = checked
            }
            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Bluetooth")
                iconName: "network-bluetooth-symbolic"
                checked: Shell.bluetoothEnabled
                onToggled: Shell.bluetoothEnabled = checked
            }
            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Airplane mode")
                iconName: "network-flightmode-on-symbolic"
                checked: Shell.airplaneMode
                onToggled: Shell.airplaneMode = checked
            }
            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Night light")
                iconName: "redshift-status-on-symbolic"
                checked: Shell.nightLight
                onToggled: Shell.nightLight = checked
            }
            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Dark mode")
                iconName: "contrast-symbolic"
                checked: Theme.dark
                onToggled: Theme.setDark(checked)
            }
            ToggleTile {
                Layout.fillWidth: true
                text: qsTr("Focus")
                iconName: "notifications-disabled-symbolic"
                checked: Shell.focusMode
                onToggled: Shell.focusMode = checked
            }
        }

        // --- Sliders ---

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            LIcon { iconName: "brightness-high-symbolic"; size: 18 }

            LSlider {
                Layout.fillWidth: true
                value: Shell.brightness
                onMoved: Shell.brightness = value
                Accessible.name: qsTr("Brightness")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            SubtleButton {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                padding: 0
                enabled: quickSettings.hasAudio
                Accessible.name: qsTr("Mute")
                onClicked: audioBackend.prefferedOutputMuted = !audioBackend.prefferedOutputMuted
                contentItem: Item {
                    LIcon {
                        anchors.centerIn: parent
                        size: 18
                        iconName: quickSettings.hasAudio && audioBackend.prefferedOutputMuted
                              ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
                    }
                }
            }

            LSlider {
                Layout.fillWidth: true
                enabled: quickSettings.hasAudio
                value: quickSettings.hasAudio && audioBackend.normalVolume > 0
                       ? audioBackend.prefferedOutputVolume / audioBackend.normalVolume : 0
                onMoved: audioBackend.prefferedOutputVolume = Math.round(value * audioBackend.normalVolume)
                Accessible.name: qsTr("Volume")
            }
        }

        // --- Personalization: accent color ---

        Card {
            Layout.fillWidth: true
            Layout.preferredHeight: accentColumn.implicitHeight + 2 * Theme.spacingM

            Column {
                id: accentColumn

                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                LText {
                    text: qsTr("Accent color") + ": " + Theme.accents[Theme.accentIndex].name
                    font.pixelSize: Theme.fontCaption
                    color: Theme.textSecondary
                }

                Row {
                    spacing: Theme.spacingS

                    Repeater {
                        model: Theme.accents

                        delegate: T.AbstractButton {
                            id: swatch

                            required property var modelData
                            required property int index
                            readonly property bool selected: index === Theme.accentIndex

                            width: 36
                            height: 36
                            hoverEnabled: true
                            Accessible.name: modelData.name
                            onClicked: Theme.setAccentIndex(index)

                            contentItem: Item {
                                // Selection ring
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.textPrimary
                                    opacity: swatch.selected ? 1 : 0
                                    Behavior on opacity { OpacityAnimator { duration: Theme.durationFast } }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: swatch.selected ? 24 : swatch.hovered ? 30 : 28
                                    height: width
                                    radius: width / 2
                                    color: Theme.dark ? swatch.modelData.dark : swatch.modelData.light

                                    Behavior on width { NumberAnimation { duration: Theme.durationNormal; easing.type: Theme.easingEnter } }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.divider
                }

                // Applies the theme colors to the applications (KDE color scheme)
                Item {
                    width: parent.width
                    height: 32

                    Column {
                        anchors.left: parent.left
                        anchors.right: appColorsSwitch.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        LText { width: parent.width; text: qsTr("Apply to applications") }
                        LText {
                            width: parent.width
                            text: qsTr("Colors of KDE and Qt apps follow the theme")
                            font.pixelSize: Theme.fontCaption
                            color: Theme.textSecondary
                        }
                    }

                    LSwitch {
                        id: appColorsSwitch

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Theme.appColors
                        onToggled: Theme.setAppColors(checked)
                        Accessible.name: qsTr("Apply colors to applications")
                    }
                }
            }
        }

        // --- Footer: battery and settings ---

        RowLayout {
            Layout.fillWidth: true

            LIcon { iconName: "battery-080-symbolic"; size: 18 }
            LText { text: "80%"; color: Theme.textSecondary }

            Item { Layout.fillWidth: true }

            SubtleButton {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                padding: 0
                Accessible.name: qsTr("All settings")
                onClicked: Shell.launch("systemsettings")
                contentItem: Item {
                    LIcon { anchors.centerIn: parent; size: 18; iconName: "configure-symbolic" }
                }
            }
        }
    }
}
