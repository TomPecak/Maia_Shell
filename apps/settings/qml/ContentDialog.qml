import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Templates as T

import LumenFrontend

// Fluent content dialog: modal, centered over the window, the primary action in the accent color
// at the right of the footer (the last thing read), Escape and the secondary button cancel.
//
//   ContentDialog { title: qsTr("Forget network?"); primaryText: qsTr("Forget"); onAccepted: ... }
T.Popup {
    id: dialog

    property string title
    property string primaryText: qsTr("OK")
    property string secondaryText: qsTr("Cancel")
    property bool primaryEnabled: true
    property bool primaryDestructive: false
    // A call is running: the buttons wait, a ring shows it
    property bool busy: false
    // An error of the last attempt, shown above the buttons
    property string error
    default property alias content: body.data

    signal accepted()
    signal rejected()

    parent: T.Overlay.overlay
    anchors.centerIn: parent
    // Templates leave the implicit size to the style
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    width: Math.min(parent ? parent.width - 2 * Theme.spacingXL : 480, 520)
    modal: true
    focus: true
    padding: 0
    closePolicy: dialog.busy ? T.Popup.NoAutoClose : T.Popup.CloseOnEscape

    function accept() {
        if (dialog.primaryEnabled && !dialog.busy)
            dialog.accepted()
    }

    onClosed: error = ""

    T.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.3)
        Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
        NumberAnimation { property: "scale"; from: 1.05; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast; easing.type: Theme.easingExit }
    }

    background: Rectangle {
        radius: Theme.radiusLarge
        color: Theme.windowContent
        border.width: 1
        border.color: Theme.stroke
    }

    contentItem: ColumnLayout {
        spacing: 0

        Flickable {
            id: scroll

            // The body scrolls when the window is too low for it; the footer stays
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(bodyColumn.implicitHeight,
                                             (dialog.parent ? dialog.parent.height - 2 * Theme.spacingXL : 720) - footerArea.implicitHeight)
            contentHeight: bodyColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: scroll.contentHeight > scroll.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff }

            ColumnLayout {
                id: bodyColumn

                x: Theme.spacingXL
                width: scroll.width - 2 * Theme.spacingXL
                spacing: Theme.spacingL

                Item { Layout.preferredHeight: Theme.spacingS }

                LText {
                    text: dialog.title
                    font.pixelSize: Theme.fontSubtitle
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    id: body

                    Layout.fillWidth: true
                    spacing: Theme.spacingL
                }

                Item { Layout.preferredHeight: Theme.spacingS }
            }
        }

        // Footer: a slightly different surface, as Fluent's dialogs
        Rectangle {
            id: footerArea

            Layout.fillWidth: true
            implicitHeight: footer.implicitHeight + 2 * Theme.spacingXL
            color: Theme.windowToolbar
            radius: Theme.radiusLarge

            // Square top corners
            Rectangle { width: parent.width; height: Theme.radiusLarge; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: Theme.divider }

            ColumnLayout {
                id: footer

                anchors.fill: parent
                anchors.margins: Theme.spacingXL
                spacing: Theme.spacingM

                LText {
                    visible: dialog.error.length > 0
                    text: dialog.error
                    color: Theme.critical
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Theme.spacingS
                    Layout.fillWidth: true

                    ProgressRing {
                        visible: dialog.busy
                        implicitWidth: 20
                        implicitHeight: 20
                        value: 0.25
                        RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: dialog.busy }
                    }

                    Item { Layout.fillWidth: true }

                    StandardButton {
                        visible: dialog.secondaryText.length > 0
                        text: dialog.secondaryText
                        enabled: !dialog.busy
                        Layout.preferredWidth: Math.max(implicitWidth, 120)
                        onClicked: {
                            dialog.rejected()
                            dialog.close()
                        }
                    }

                    AccentButton {
                        text: dialog.primaryText
                        enabled: dialog.primaryEnabled && !dialog.busy
                        opacity: enabled ? 1 : 0.45
                        Layout.preferredWidth: Math.max(implicitWidth, 120)
                        onClicked: dialog.accept()
                    }
                }
            }
        }
    }
}
