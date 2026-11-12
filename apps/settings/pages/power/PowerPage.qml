import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import LumenFrontend
import Maia.SettingsKit
import Maia.Power

import "Texts.js" as Texts

// Settings › Power, laid out like GNOME's Power panel (Ubuntu 24.04 / 26.04): the battery first
// (what people come for), the devices' batteries, the power mode, then brightness (GNOME has it
// in the quick settings only; here it sits with the other things maia-power-service does).
// What the machine lacks is left out, not shown disabled: no battery on a desktop, no
// power-profiles-daemon, no backlight.
SettingsPage {
    id: page

    title: qsTr("Power")

    readonly property bool showBattery: Power.hasBattery
    readonly property bool showDevices: devices.count > 0
    readonly property bool showProfiles: Power.profilesAvailable && Power.profiles.length > 0
    readonly property bool showBrightness: displays.count > 0 || Power.keyboardBrightnessAvailable

    BatteriesModel { id: devices; devicesOnly: true }
    DisplaysModel { id: displays }

    // --- The service is missing, or the machine has nothing to set ---

    EmptyState {
        visible: !Power.connected
        iconName: "battery-missing-symbolic"
        title: qsTr("Power settings unavailable")
        description: qsTr("The power service (maia-power-service) is not running.")
    }

    EmptyState {
        visible: Power.connected && !page.showBattery && !page.showDevices && !page.showProfiles && !page.showBrightness
        iconName: "computer-symbolic"
        title: qsTr("Nothing to set on this computer")
        description: qsTr("It has no battery, no adjustable screen brightness and no power modes.")
    }

    // --- Battery ---

    InfoBar {
        visible: page.showBattery && Power.onBattery && Power.warningLevel !== Power.NoWarning
        severity: Power.warningLevel === Power.LowWarning ? "warning" : "error"
        title: Power.warningLevel === Power.LowWarning ? qsTr("Battery low") : qsTr("Battery critically low")
        message: Power.warningLevel === Power.LowWarning
                 ? qsTr("Connect the charger soon, or choose Power Saver to make the battery last longer.")
                 : qsTr("Connect the charger now. The computer will soon turn off to save your work.")
    }

    SettingsGroup {
        visible: page.showBattery
        title: qsTr("Battery")

        SettingsCard {
            iconName: Texts.batteryIcon(Power.batteryPercentage, Power.batteryState)
            title: Texts.batteryState(Power.batteryState, Power.timeToEmpty, Power.timeToFull)
            description: Power.batteryCapacity > 0
                         ? qsTr("Battery health: %1 % of its original capacity").arg(Math.round(Power.batteryCapacity))
                         : ""

            LevelBar {
                percentage: Power.batteryPercentage
                low: Power.warningLevel !== Power.NoWarning
            }
        }
    }

    // --- Devices: a mouse, headphones, a phone ---

    SettingsGroup {
        visible: page.showDevices
        title: qsTr("Devices")

        Repeater {
            model: devices

            SettingsCard {
                iconName: Texts.deviceIcon(model.kind)
                title: model.modelName.length > 0 ? model.modelName : Texts.deviceKind(model.kind)
                description: model.state === Power.Charging || model.state === Power.Full
                             ? Texts.batteryState(model.state, 0, model.timeToFull)
                             : (model.vendor.length > 0 ? model.vendor : Texts.deviceKind(model.kind))

                LevelBar {
                    percentage: model.percentage
                    low: model.warningLevel !== Power.NoWarning
                }
            }
        }
    }

    // --- Power mode ---

    SettingsGroup {
        visible: page.showProfiles
        title: qsTr("Power Mode")

        // An application chose the mode for the time being (a game, a compiler)
        Repeater {
            model: Power.profileHolds

            InfoBar {
                required property var modelData

                severity: "info"
                title: qsTr("%1 is on for “%2”").arg(Texts.profileName(modelData.profile))
                                                .arg(modelData.applicationId.length > 0 ? modelData.applicationId : qsTr("an application"))
                message: (modelData.reason.length > 0 ? modelData.reason + ". " : "")
                         + qsTr("Choosing a mode yourself ends it.")
            }
        }

        InfoBar {
            visible: Power.performanceDegraded !== Power.NotDegraded && Power.profile === Power.Performance
            severity: "warning"
            title: qsTr("Performance mode is limited")
            message: Texts.degradation(Power.performanceDegraded)
        }

        // In GNOME's order: the fastest first
        Repeater {
            model: [Power.Performance, Power.Balanced, Power.PowerSaver].filter(profile => Power.profiles.indexOf(profile) >= 0)

            ProfileCard {
                required property int modelData

                profile: modelData
                checked: Power.profile === modelData
                onClicked: Power.profile = modelData
            }
        }
    }

    // --- Brightness ---

    SettingsGroup {
        visible: page.showBrightness
        title: qsTr("Brightness")

        Repeater {
            model: displays

            SettingsCard {
                id: displayCard

                // The built-in screen goes through Power: a dragged slider is thinned out and the
                // service's echoes do not move it back
                readonly property bool builtIn: model.kind === 0
                readonly property real level: builtIn ? Power.brightness : model.brightness

                iconName: "brightness-high-symbolic"
                title: builtIn ? qsTr("Screen brightness") : qsTr("Brightness of %1").arg(model.device)

                Row {
                    spacing: Theme.spacingM

                    LSlider {
                        width: 240
                        from: 0
                        to: 1
                        value: displayCard.level
                        Accessible.name: displayCard.title
                        onMoved: {
                            const level = Math.max(value, model.minimum)
                            if (displayCard.builtIn)
                                Power.brightness = level
                            else
                                displays.setBrightness(model.id, level)
                        }
                    }

                    LText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        horizontalAlignment: Text.AlignRight
                        text: qsTr("%1 %").arg(Math.round(displayCard.level * 100))
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        SettingsCard {
            id: keyboardCard

            // The keyboard's own levels (often 0, 1, 2): the slider stops at each
            readonly property int steps: Math.max(1, Power.keyboardBrightnessSteps)

            visible: Power.keyboardBrightnessAvailable
            iconName: "input-keyboard-symbolic"
            title: qsTr("Keyboard backlight")

            Row {
                spacing: Theme.spacingM

                LSlider {
                    width: 240
                    from: 0
                    to: keyboardCard.steps
                    stepSize: 1
                    snapMode: T.Slider.SnapAlways
                    value: Math.round(Power.keyboardBrightness * keyboardCard.steps)
                    Accessible.name: keyboardCard.title
                    onMoved: Power.keyboardBrightness = value / keyboardCard.steps
                }

                LText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignRight
                    text: Power.keyboardBrightness > 0 ? qsTr("%1 %").arg(Math.round(Power.keyboardBrightness * 100)) : qsTr("Off")
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    Item { Layout.preferredHeight: Theme.spacingXL }

    // --- Testing: maia-settings --page power --action hold (an application holds Performance),
    // --action end (scrolled to the end) ---

    ProfileHold {
        id: testHold

        profile: Power.Performance
        reason: "Compiling Maia"
        applicationId: "org.maia.terminal"
    }

    Timer {
        running: SettingsApp.testAction.length > 0
        interval: 800
        onTriggered: {
            const action = SettingsApp.testAction
            SettingsApp.testAction = ""
            if (action === "hold")
                testHold.active = true
            else if (action === "end")
                page.contentItem.contentY = Math.max(0, page.contentItem.contentHeight - page.height)
        }
    }
}
