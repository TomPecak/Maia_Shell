pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Templates as T
import org.kde.layershell 1.0 as LayerShell

import Maia.Backend as Maia

import LumenFrontend
import "../services"

// Kitchen timer: a widget always visible in the bottom-right corner, above the taskbar.
//
// - quick start: one tap on a preset (3, 5, 8, 10, 15 min) starts the countdown,
// - own time: the mouse wheel over the time adds / removes a minute, then the play button,
// - while counting: pause / resume, -1 / +1 / +5 min, reset,
// - alarm: the card glows and pulses, a sound plays (up to a minute); stop or snooze.
// The widget collapses into a small pill showing the remaining time. It steps aside while
// the calendar or the quick settings (the same corner) are open, except during the alarm.
//
// The window has a fixed size, the card inside changes its shape (expanded card / pill);
// the transparent rest of the window does not receive input (MaskArea).
Window {
    id: timerWindow

    readonly property int margin: Theme.spacingM
    readonly property int expandedWidth: 320
    readonly property int expandedHeight: 184
    readonly property int collapsedWidth: 156
    readonly property int collapsedHeight: 44
    readonly property int padding: Theme.spacingL

    readonly property bool finished: countdown.status === "finished"
    // The alarm always shows the whole widget
    readonly property bool collapsed: countdown.settings.collapsed && !finished
    // The calendar and the quick settings open in the same corner
    readonly property bool shown: finished
                                  || (Shell.activeFlyout !== "calendar" && Shell.activeFlyout !== "quickSettings")

    // Progress shown by the rings, animated smoothly between the ticks of the countdown
    property real ringValue: 1

    function syncRing() {
        ringAnimation.stop()
        ringValue = countdown.status === "idle" ? 1 : countdown.fraction
        if (countdown.status === "running") {
            ringAnimation.duration = Math.max(1, countdown.remaining)
            ringAnimation.start()
        }
    }

    function addTime(ms) {
        countdown.add(ms)
        syncRing()
    }

    width: expandedWidth + 2 * margin
    height: expandedHeight + 2 * margin
    color: "transparent"
    flags: Qt.FramelessWindowHint
    transientParent: null
    visible: true

    LayerShell.Window.scope: "lumen-timer"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: 0
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    onShownChanged: {
        if (shown) {
            hideAnimation.stop()
            showAnimation.restart()
        } else {
            showAnimation.stop()
            hideAnimation.restart()
        }
    }

    Component.onCompleted: showAnimation.start()

    CountdownTimer {
        id: countdown

        onElapsed: {
            if (soundLoader.item)
                soundLoader.item.play()
            shake.restart()
        }
        onStatusChanged: {
            if (status !== "finished" && soundLoader.item)
                soundLoader.item.stop()
            timerWindow.syncRing()
        }
        onTotalChanged: timerWindow.syncRing()
    }

    NumberAnimation {
        id: ringAnimation

        target: timerWindow
        property: "ringValue"
        to: 0
    }

    // Sound of the alarm, optional (QtMultimedia)
    Loader {
        id: soundLoader

        source: Qt.resolvedUrl("../services/TimerSound.qml")
    }

    // --- Show / hide ---

    ParallelAnimation {
        id: showAnimation

        OpacityAnimator { target: motion; to: 1; duration: Theme.durationSlow; easing.type: Theme.easingEnter }
        YAnimator { target: motion; to: 0; duration: Theme.durationSlow; easing.type: Theme.easingEnter }
    }

    ParallelAnimation {
        id: hideAnimation

        OpacityAnimator { target: motion; to: 0; duration: Theme.durationFast; easing.type: Theme.easingExit }
        YAnimator { target: motion; to: Theme.flyoutOffset / 2; duration: Theme.durationFast; easing.type: Theme.easingExit }
    }

    // --- Alarm effects ---

    // Draws attention once, when the time is up
    SequentialAnimation {
        id: shake

        XAnimator { target: motion; to: -6; duration: 60; easing.type: Easing.OutQuad }
        XAnimator { target: motion; to: 6; duration: 90; easing.type: Easing.InOutQuad }
        XAnimator { target: motion; to: -4; duration: 80; easing.type: Easing.InOutQuad }
        XAnimator { target: motion; to: 3; duration: 70; easing.type: Easing.InOutQuad }
        XAnimator { target: motion; to: 0; duration: 60; easing.type: Easing.OutQuad }
    }

    // Pulses while the alarm lasts
    SequentialAnimation {
        id: alarmPulse

        running: timerWindow.finished
        loops: Animation.Infinite

        ParallelAnimation {
            OpacityAnimator { target: glow; from: 0.15; to: 0.8; duration: 520; easing.type: Easing.InOutSine }
            ScaleAnimator { target: ring; from: 1; to: 1.07; duration: 520; easing.type: Easing.InOutSine }
            OpacityAnimator { target: timeText; from: 1; to: 0.45; duration: 520; easing.type: Easing.InOutSine }
        }
        ParallelAnimation {
            OpacityAnimator { target: glow; from: 0.8; to: 0.15; duration: 520; easing.type: Easing.InOutSine }
            ScaleAnimator { target: ring; from: 1.07; to: 1; duration: 520; easing.type: Easing.InOutSine }
            OpacityAnimator { target: timeText; from: 0.45; to: 1; duration: 520; easing.type: Easing.InOutSine }
        }

        onRunningChanged: {
            if (running)
                return
            glow.opacity = 0
            ring.scale = 1
            timeText.opacity = 1
        }
    }

    // --- The card ---

    Item {
        id: cardArea

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: timerWindow.margin
        width: timerWindow.collapsed ? timerWindow.collapsedWidth : timerWindow.expandedWidth
        height: timerWindow.collapsed ? timerWindow.collapsedHeight : timerWindow.expandedHeight

        Behavior on width { NumberAnimation { duration: Theme.durationSlow; easing.type: Theme.easingStandard } }
        Behavior on height { NumberAnimation { duration: Theme.durationSlow; easing.type: Theme.easingStandard } }

        // Animated part: shown / hidden and shaken by the alarm
        Item {
            id: motion

            width: cardArea.width
            height: cardArea.height
            y: Theme.flyoutOffset / 2
            opacity: 0

            // Accent glow of the alarm
            RectangularShadow {
                id: glow

                anchors.fill: card
                radius: card.radius
                blur: 28
                spread: 2
                color: Theme.accent
                opacity: 0
            }

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                offset.y: 6
                blur: 20
                spread: 0
                color: Theme.shadow
            }

            Rectangle {
                id: card

                // Morphs from the rounded card into the pill
                property real cornerRadius: timerWindow.collapsed ? timerWindow.collapsedHeight / 2 : Theme.radiusLarge

                anchors.fill: parent
                radius: Math.min(height / 2, cornerRadius)
                color: Theme.surface
                border.width: 1
                border.color: timerWindow.finished ? Theme.accent : Theme.stroke
                clip: true

                Behavior on cornerRadius { NumberAnimation { duration: Theme.durationSlow; easing.type: Theme.easingStandard } }
                Behavior on color { ColorAnimation { duration: Theme.durationNormal } }
                Behavior on border.color { ColorAnimation { duration: Theme.durationNormal } }

                // Expanded card
                Item {
                    id: expanded

                    readonly property bool active: !timerWindow.collapsed

                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: timerWindow.expandedWidth
                    height: timerWindow.expandedHeight
                    opacity: active ? 1 : 0
                    // Stays visible until it has faded out (the Animator updates the opacity at its end)
                    visible: active || opacity > 0

                    Behavior on opacity {
                        OpacityAnimator { duration: expanded.active ? Theme.durationSlow : Theme.durationFast }
                    }

                    // Header
                    Row {
                        x: timerWindow.padding
                        y: 14
                        spacing: Theme.spacingS

                        LIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "chronometer-symbolic"
                            size: 14
                            tint: Theme.textSecondary
                        }
                        LText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Timer")
                            font.pixelSize: Theme.fontCaption
                            font.weight: Font.DemiBold
                            color: Theme.textSecondary
                        }
                    }

                    SubtleButton {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        y: Theme.spacingS
                        width: 28
                        height: 28
                        padding: 0
                        radius: 14
                        Accessible.name: qsTr("Collapse")
                        onClicked: countdown.settings.collapsed = true

                        contentItem: Item {
                            LIcon {
                                anchors.centerIn: parent
                                iconName: "go-down-symbolic"
                                size: 12
                                tint: Theme.textSecondary
                            }
                        }
                    }

                    // Ring with the main action, the time and the reset
                    Item {
                        id: mainRow

                        x: timerWindow.padding
                        y: 44
                        width: parent.width - 2 * timerWindow.padding
                        height: 72

                        ProgressRing {
                            id: ring

                            width: 72
                            height: 72
                            thickness: 5
                            value: timerWindow.ringValue
                        }

                        PlayButton {
                            anchors.centerIn: ring
                        }

                        Column {
                            anchors.left: ring.right
                            anchors.leftMargin: Theme.spacingL
                            anchors.verticalCenter: ring.verticalCenter
                            spacing: 2

                            LText {
                                id: timeText

                                text: countdown.format(countdown.remaining)
                                font.pixelSize: 36
                                font.weight: Font.DemiBold
                                // Digits of the same width, the time does not wobble while counting
                                font.features: ({ "tnum": 1 })
                                color: timerWindow.finished ? Theme.accent
                                     : countdown.status === "paused" ? Theme.textSecondary
                                     : Theme.textPrimary
                            }

                            LText {
                                text: {
                                    switch (countdown.status) {
                                    case "running":
                                        return qsTr("Ends at %1").arg(Qt.formatTime(new Date(countdown.endTime),
                                                                                     Qt.locale().timeFormat(Locale.ShortFormat)))
                                    case "paused":
                                        return qsTr("Paused")
                                    case "finished":
                                        return qsTr("Time's up!")
                                    default:
                                        return qsTr("Scroll to set the time")
                                    }
                                }
                                font.pixelSize: Theme.fontCaption
                                font.weight: timerWindow.finished ? Font.DemiBold : Font.Normal
                                color: timerWindow.finished ? Theme.accent : Theme.textSecondary
                            }
                        }

                        // The mouse wheel over the ring and the time adds / removes a minute
                        WheelHandler {
                            property real accumulated: 0

                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                accumulated += event.angleDelta.y
                                while (Math.abs(accumulated) >= 120) {
                                    const step = accumulated > 0 ? 1 : -1
                                    accumulated -= step * 120
                                    if (!timerWindow.finished)
                                        timerWindow.addTime(step * 60 * 1000)
                                }
                            }
                        }

                        SubtleButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: ring.verticalCenter
                            width: 32
                            height: 32
                            padding: 0
                            radius: 16
                            enabled: countdown.active
                            opacity: enabled ? 1 : 0
                            Accessible.name: qsTr("Reset")
                            onClicked: countdown.reset()

                            Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }

                            contentItem: Item {
                                LIcon {
                                    anchors.centerIn: parent
                                    iconName: "view-refresh-symbolic"
                                    size: 16
                                    tint: Theme.textSecondary
                                }
                            }
                        }
                    }

                    // Quick actions, they change with the state of the timer
                    Item {
                        x: timerWindow.padding
                        y: parent.height - timerWindow.padding - 30
                        width: parent.width - 2 * timerWindow.padding
                        height: 30

                        ChipRow {
                            active: countdown.status === "idle"
                            actions: [3, 5, 8, 10, 15].map(minutes => ({
                                label: qsTr("%1 min").arg(minutes),
                                selected: countdown.duration === minutes * 60 * 1000,
                                run: () => countdown.start(minutes * 60 * 1000)
                            }))
                        }

                        ChipRow {
                            active: countdown.active
                            actions: [
                                { label: qsTr("−1 min"), run: () => timerWindow.addTime(-60 * 1000) },
                                { label: qsTr("+1 min"), run: () => timerWindow.addTime(60 * 1000) },
                                { label: qsTr("+5 min"), run: () => timerWindow.addTime(5 * 60 * 1000) }
                            ]
                        }

                        ChipRow {
                            active: timerWindow.finished
                            actions: [
                                { label: qsTr("+1 min"), run: () => timerWindow.addTime(60 * 1000) },
                                { label: qsTr("+5 min"), run: () => timerWindow.addTime(5 * 60 * 1000) },
                                { label: qsTr("Stop"), accent: true, run: () => countdown.reset() }
                            ]
                        }
                    }
                }

                // Collapsed pill
                T.AbstractButton {
                    id: pill

                    readonly property bool active: timerWindow.collapsed

                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: timerWindow.collapsedWidth
                    height: timerWindow.collapsedHeight
                    hoverEnabled: true
                    opacity: active ? 1 : 0
                    visible: active || opacity > 0
                    enabled: active
                    Accessible.name: qsTr("Timer: %1").arg(countdown.format(countdown.remaining))
                    onClicked: countdown.settings.collapsed = false

                    Behavior on opacity {
                        OpacityAnimator { duration: pill.active ? Theme.durationSlow : Theme.durationFast }
                    }

                    background: Rectangle {
                        radius: height / 2
                        color: pill.pressed ? Theme.subtlePressed : pill.hovered ? Theme.subtleHover : "transparent"

                        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    }

                    contentItem: Item {
                        ProgressRing {
                            id: miniRing

                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26
                            thickness: 3
                            value: timerWindow.ringValue
                            opacity: countdown.status === "idle" ? 0 : 1

                            Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
                        }

                        LIcon {
                            anchors.centerIn: miniRing
                            iconName: "chronometer-symbolic"
                            size: 16
                            tint: Theme.textSecondary
                            opacity: countdown.status === "idle" ? 1 : 0

                            Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
                        }

                        LText {
                            anchors.left: miniRing.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: countdown.status === "idle" ? qsTr("Timer") : countdown.format(countdown.remaining)
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                            color: countdown.status === "paused" ? Theme.textSecondary : Theme.textPrimary
                        }

                        LIcon {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "go-up-symbolic"
                            size: 10
                            tint: Theme.textTertiary
                        }
                    }
                }
            }
        }

        // Only the card receives input
        Maia.MaskArea {
            anchors.fill: parent
            visible: timerWindow.shown
        }
    }



    // --- Building blocks ---

    // Round accent button inside the ring: start, pause / resume, stop the alarm
    component PlayButton: T.AbstractButton {
        id: play

        readonly property string status: countdown.status

        width: 48
        height: 48
        hoverEnabled: true
        Accessible.name: status === "running" ? qsTr("Pause")
                       : status === "paused" ? qsTr("Resume")
                       : status === "finished" ? qsTr("Stop the alarm")
                       : qsTr("Start")
        onClicked: countdown.toggle()

        scale: pressed ? 0.9 : 1
        Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }

        background: Rectangle {
            radius: width / 2
            color: play.pressed ? Theme.accentPressed : play.hovered ? Theme.accentHover : Theme.accent

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }

        contentItem: Item {
            PlayIcon { iconName: "media-playback-start-symbolic"; shown: play.status === "idle" || play.status === "paused"; offsetX: 1 }
            PlayIcon { iconName: "media-playback-pause-symbolic"; shown: play.status === "running" }
            PlayIcon { iconName: "media-playback-stop-symbolic"; shown: play.status === "finished" }
        }
    }

    // Icon of the play button, the icons cross-fade and pop when the state changes
    component PlayIcon: LIcon {
        property bool shown: false
        property real offsetX: 0

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: offsetX
        size: 18
        tint: Theme.onAccent
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.6

        Behavior on opacity { OpacityAnimator { duration: Theme.durationNormal } }
        Behavior on scale { ScaleAnimator { duration: Theme.durationNormal; easing.type: Easing.OutBack } }
    }

    // Row of equally wide chips, cross-fades with the other rows
    component ChipRow: Row {
        id: row

        property bool active: false
        // [{ label, run, selected?, accent? }]
        property var actions: []

        width: parent.width
        spacing: 6
        opacity: active ? 1 : 0
        visible: active || opacity > 0
        enabled: active

        Behavior on opacity {
            OpacityAnimator { duration: row.active ? Theme.durationNormal : Theme.durationFast }
        }

        Repeater {
            model: row.actions

            delegate: Chip {
                required property var modelData

                width: (row.width - (row.actions.length - 1) * row.spacing) / row.actions.length
                text: modelData.label
                selected: modelData.selected === true
                accent: modelData.accent === true
                onClicked: modelData.run()
            }
        }
    }

    component Chip: T.AbstractButton {
        id: chip

        property bool selected: false
        property bool accent: false

        height: 30
        hoverEnabled: true
        Accessible.name: text

        scale: pressed ? 0.95 : 1
        Behavior on scale { ScaleAnimator { duration: Theme.durationFast; easing.type: Theme.easingEnter } }

        background: Rectangle {
            radius: height / 2
            color: chip.accent ? (chip.pressed ? Theme.accentPressed : chip.hovered ? Theme.accentHover : Theme.accent)
                 : chip.pressed ? Theme.subtlePressed
                 : chip.hovered ? Theme.controlStrong
                 : Theme.control
            border.width: chip.selected ? 1.5 : 1
            border.color: chip.selected ? Theme.accent : Theme.stroke

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
        }

        contentItem: LText {
            text: chip.text
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontCaption
            font.weight: chip.selected || chip.accent ? Font.DemiBold : Font.Normal
            font.features: ({ "tnum": 1 })
            color: chip.accent ? Theme.onAccent : chip.selected ? Theme.accent : Theme.textPrimary
        }
    }
}
