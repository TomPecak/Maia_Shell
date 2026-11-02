pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import Maia.Backend as Maia
import MaiaFrontend

// Session screen: sleep, restart, shut down and log out, opened by the power button of the status
// area.
//
// A full-screen, modal screen, like the power-off screen and the Control Center of iPadOS: ending
// the session is a decision about the whole computer, so it takes the whole screen. The desktop
// is always dimmed (modality: the rest waits), while the cards on it follow the light or dark
// mode like every other surface of the frontend (internal consistency; the mode is the user's
// choice). In the middle the user, so it is clear whose session ends, and below the actions in
// two groups (common region): the power actions in the order of macOS (Sleep, Restart, Shut Down;
// Shut Down red in both modes, it is the destructive one) and, apart from them, Log Out. Cancel
// at the bottom; Escape and a click outside cancel too.
//
// Opening the screen is the confirmation step (a deliberate click on the power button), so the
// actions act at once, without another dialog: the screen fades to black and the action is
// carried out. If the session is still there a few seconds later (sleep and wake up, logind
// refused, a nested development session), the screen comes back and closes.
//
// Fills the whole window; the input region covers it only while it is shown.
Item {
    id: screen

    property bool open: false

    // The screen asks to be closed (Cancel, Escape, a click outside)
    signal closeRequested()
    // The screen closed without ending the session: the window that had the keyboard before
    // should get it back
    signal dismissed()

    // Shown from opening until the closing animation has finished (Animators, see MenuPanel.qml)
    property bool shown: false

    visible: shown

    onOpenChanged: open ? d.show() : d.hide()

    // The user name, from the home directory of the session
    readonly property string userName: typeof HOME !== "undefined" && HOME
                                       ? String(HOME).split("/").filter(part => part.length > 0).pop() || "" : ""

    // --- Actions ---

    readonly property var powerActions: [
        { id: "suspend", text: qsTr("Sleep"), icon: d.icon("system-suspend-symbolic"),
          available: Maia.MSessionManager.canSuspend, destructive: false },
        { id: "reboot", text: qsTr("Restart"), icon: d.icon("system-reboot-symbolic"),
          available: Maia.MSessionManager.canReboot, destructive: false },
        { id: "shutdown", text: qsTr("Shut Down"), icon: d.icon("system-shutdown-symbolic"),
          available: Maia.MSessionManager.canPowerOff, destructive: true }
    ].filter(action => action.available)

    readonly property var sessionActions: [
        { id: "logout", text: qsTr("Log Out"), icon: d.icon("system-log-out-symbolic"), destructive: false }
    ]

    // Keyboard order: the actions from left to right, then Cancel
    readonly property var keyboardOrder: powerActions.concat(sessionActions).map(action => action.id).concat(["cancel"])

    // Carries out an action: the screen fades to black, then Maia ends the session (logind for the
    // power actions; only logged in a nested development session)
    function perform(actionId) {
        if (d.performing)
            return
        console.log("[SessionScreen]", actionId)
        d.performing = actionId
        blackoutAnimation.restart()
    }

    // --- Dimming ---

    Rectangle {
        id: scrim

        anchors.fill: parent
        // Dark enough that the windows below step back behind the cards (there is no blur); in
        // the dark mode darker, so the dark cards still stand apart
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.6 : 0.32)
        opacity: 0

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: {
                if (!d.performing)
                    screen.closeRequested()
            }
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Maia.MaskArea {
            anchors.fill: parent
        }
    }

    // --- Content ---

    // Takes the keyboard while the screen is open
    Item {
        id: keyHandler

        focus: true
        Keys.onPressed: function (event) { d.handleKey(event) }
    }

    Column {
        id: content

        anchors.centerIn: parent
        // A little above the middle: the eye rests there, and Cancel has room below
        anchors.verticalCenterOffset: -32
        spacing: 40

        // Whose session it is, on a card of its own: text straight on the dimmed desktop would be
        // hard to read on a light wallpaper
        Rectangle {
            id: header

            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(200, headerColumn.width + 2 * 32)
            height: headerColumn.height + 2 * 22
            radius: 30
            color: Theme.card
            border.width: 1
            border.color: Theme.hairline
            opacity: 0

            CardShadow { radius: header.radius }

            Column {
                id: headerColumn

                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    id: avatar

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 84
                    height: 84
                    radius: width / 2
                    // The placeholder of iPadOS contacts: a grey gradient with the initial
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#a5a5ab" }
                        GradientStop { position: 1; color: "#6e6e73" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: screen.userName.length > 0 ? screen.userName.charAt(0).toUpperCase() : ""
                        color: "white"
                        font.pixelSize: 36
                        font.weight: Font.DemiBold
                    }

                    // The KDE user picture, when there is one
                    Image {
                        id: picture

                        anchors.fill: parent
                        source: typeof HOME !== "undefined" && HOME ? "file://" + HOME + "/.face.icon" : ""
                        sourceSize: Qt.size(168, 168)
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        asynchronous: true
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: picture
                        visible: picture.status === Image.Ready
                        maskEnabled: true
                        maskSource: avatarMask
                    }

                    Rectangle {
                        id: avatarMask

                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: screen.userName
                    color: Theme.label
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }
            }
        }

        // The actions in two groups
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 20

            Platter {
                id: powerPlatter

                actions: screen.powerActions
            }

            Platter {
                id: sessionPlatter

                actions: screen.sessionActions
            }
        }
    }

    // Shadow below a card (a child with a negative z is drawn below its parent); radius: the
    // card's corner radius
    component CardShadow: RectangularShadow {
        z: -1
        anchors.fill: parent
        offset.y: 10
        blur: 36
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.16)
    }

    // A card holding one group of actions, like a platter of the Control Center
    component Platter: Rectangle {
        id: platter

        property var actions: []

        width: platterRow.width + 2 * 16
        height: platterRow.height + 2 * 18
        radius: 30
        // Opaque: without blur, a translucent card would show the windows below
        color: Theme.card
        border.width: 1
        border.color: Theme.hairline
        visible: actions.length > 0
        opacity: 0

        CardShadow { radius: platter.radius }

        Row {
            id: platterRow

            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: platter.actions

                SessionActionButton {
                    required property var modelData

                    text: modelData.text
                    iconName: modelData.icon
                    destructive: modelData.destructive
                    selected: d.selection === modelData.id
                    opacity: d.performing && d.performing !== modelData.id ? 0.35 : 1

                    Behavior on opacity {
                        OpacityAnimator { duration: 200 }
                    }

                    onClicked: screen.perform(modelData.id)
                }
            }
        }
    }

    // Cancel, at the bottom like on the power-off screen of iPadOS
    Rectangle {
        id: cancelButton

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: content.bottom
        anchors.topMargin: 56
        width: Math.max(140, cancelLabel.implicitWidth + 48)
        height: 44
        radius: height / 2
        color: cancelArea.containsMouse || d.selection === "cancel" ? Theme.plateHover : Theme.card
        border.width: d.selection === "cancel" ? 3 : 1
        border.color: d.selection === "cancel" ? Theme.accent : Theme.hairline
        opacity: 0

        CardShadow { radius: cancelButton.radius }

        Accessible.role: Accessible.Button
        Accessible.name: cancelLabel.text
        Accessible.onPressAction: screen.closeRequested()

        Behavior on color {
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Text {
            id: cancelLabel

            anchors.centerIn: parent
            text: qsTr("Cancel")
            // The non-destructive way out, in the accent color like Cancel in iPadOS
            color: Theme.accent
            font.pixelSize: 17
            font.weight: Font.Medium
        }

        MouseArea {
            id: cancelArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (!d.performing)
                    screen.closeRequested()
            }
        }
    }

    // Covers everything while the session ends
    Rectangle {
        id: blackout

        anchors.fill: parent
        color: "black"
        opacity: 0
    }

    // --- Animations (Animators: they run in the render thread) ---

    // Opening: the desktop darkens, the parts come up one after another, each with a soft spring
    // from slightly smaller (the eye follows them from the user down to Cancel)
    ParallelAnimation {
        id: openAnimation

        OpacityAnimator { target: scrim; to: 1; duration: 280; easing.type: Easing.OutCubic }

        SequentialAnimation {
            PauseAnimation { duration: 30 }
            ParallelAnimation {
                OpacityAnimator { target: header; to: 1; duration: 220; easing.type: Easing.OutCubic }
                ScaleAnimator { target: header; from: 0.9; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                OpacityAnimator { target: powerPlatter; to: 1; duration: 220; easing.type: Easing.OutCubic }
                ScaleAnimator { target: powerPlatter; from: 0.9; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                OpacityAnimator { target: sessionPlatter; to: 1; duration: 220; easing.type: Easing.OutCubic }
                ScaleAnimator { target: sessionPlatter; from: 0.9; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 170 }
            ParallelAnimation {
                OpacityAnimator { target: cancelButton; to: 1; duration: 220; easing.type: Easing.OutCubic }
                ScaleAnimator { target: cancelButton; from: 0.9; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }
    }

    // Closing: everything fades out together, the content shrinking slightly, quicker than it came
    ParallelAnimation {
        id: closeAnimation

        onFinished: screen.shown = screen.open

        OpacityAnimator { target: scrim; to: 0; duration: 240; easing.type: Easing.OutCubic }
        OpacityAnimator { target: header; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScaleAnimator { target: header; to: 0.95; duration: 160; easing.type: Easing.InCubic }
        OpacityAnimator { target: powerPlatter; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScaleAnimator { target: powerPlatter; to: 0.95; duration: 160; easing.type: Easing.InCubic }
        OpacityAnimator { target: sessionPlatter; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScaleAnimator { target: sessionPlatter; to: 0.95; duration: 160; easing.type: Easing.InCubic }
        OpacityAnimator { target: cancelButton; to: 0; duration: 160; easing.type: Easing.InCubic }
        ScaleAnimator { target: cancelButton; to: 0.95; duration: 160; easing.type: Easing.InCubic }
    }

    // The session ends: the screen goes black, then the action is carried out
    SequentialAnimation {
        id: blackoutAnimation

        PauseAnimation { duration: 150 }
        OpacityAnimator { target: blackout; from: 0; to: 1; duration: 450; easing.type: Easing.InOutCubic }
        ScriptAction { script: d.carryOut() }
    }

    // The session is still there: back from black, then the screen closes
    SequentialAnimation {
        id: recoverAnimation

        OpacityAnimator { target: blackout; to: 0; duration: 400; easing.type: Easing.InOutCubic }
        ScriptAction {
            script: {
                d.performing = ""
                screen.closeRequested()
            }
        }
    }

    // How long the session may take to end before the screen comes back
    Timer {
        id: recoverTimer

        interval: 4000
        onTriggered: {
            console.log("[SessionScreen] the session is still there, back to the desktop")
            recoverAnimation.restart()
        }
    }

    // --- Private ---

    QtObject {
        id: d

        // A symbolic icon shipped with the frontend (assets/icons/README.md), not one of the
        // icon theme: a theme without it would give a filled square
        function icon(name) {
            return Qt.resolvedUrl("../../assets/icons/" + name + ".svg")
        }

        // The action being carried out ("" when none)
        property string performing: ""
        // The keyboard selection ("" when none; nothing is selected at first, so Enter alone
        // never ends the session)
        property string selection: ""

        function show() {
            closeAnimation.stop()
            recoverAnimation.stop()
            recoverTimer.stop()
            performing = ""
            selection = ""
            blackout.opacity = 0
            if (!screen.shown) {
                scrim.opacity = 0
                for (const item of [header, powerPlatter, sessionPlatter, cancelButton]) {
                    item.opacity = 0
                    item.scale = 0.9
                }
            }
            screen.shown = true
            openAnimation.restart()
            if (screen.Window.window)
                screen.Window.window.requestActivate()
            keyHandler.forceActiveFocus()
        }

        function hide() {
            openAnimation.stop()
            closeAnimation.restart()
            if (!performing)
                screen.dismissed()
        }

        function carryOut() {
            switch (performing) {
            case "suspend":
                Maia.MSessionManager.suspend()
                break
            case "reboot":
                Maia.MSessionManager.reboot()
                break
            case "shutdown":
                Maia.MSessionManager.poweroff()
                break
            case "logout":
                Maia.MSessionManager.logout()
                break
            }
            recoverTimer.restart()
        }

        function handleKey(event) {
            if (performing) {
                event.accepted = true
                return
            }
            const order = screen.keyboardOrder
            const current = order.indexOf(selection)
            switch (event.key) {
            case Qt.Key_Escape:
                screen.closeRequested()
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (selection === "cancel")
                    screen.closeRequested()
                else if (selection)
                    screen.perform(selection)
                break
            case Qt.Key_Right:
            case Qt.Key_Tab:
                selection = order[current < 0 ? 0 : Math.min(order.length - 1, current + 1)]
                break
            case Qt.Key_Left:
            case Qt.Key_Backtab:
                selection = order[current < 0 ? 0 : Math.max(0, current - 1)]
                break
            case Qt.Key_Down:
                selection = "cancel"
                break
            case Qt.Key_Up:
                if (selection === "cancel" || current < 0)
                    selection = order[0]
                break
            default:
                return
            }
            event.accepted = true
        }
    }
}
