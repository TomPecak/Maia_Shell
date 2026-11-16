pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import LumenFrontend

import "ActionGlyphs.js" as ActionGlyphs

// A notification: its application and time, title, text (a little markup), a picture, its files
// (NotificationFiles), its actions (text, or icons when the sender asks) and an answer field. Used by the popups and by the notification center; the data comes from
// Maia.Notifications.Center, this card only shows it.
//
// The whole card is the target of the default action (when the notification has one); the close
// button and the actions sit on top of it.
Card {
    id: card

    property string appName
    // A theme icon name, a file URL, or one of Lumen's symbolic glyphs (assets/icons)
    property string iconName
    property string desktopEntry
    property string title
    // StyledText: <b> <i> <u> <a> <br/> (made safe by the service)
    property string body
    property date time
    property string image
    // [{ key, label }] without "default"
    property var actions: []
    // The keys are icon names (a media player's ⏮ ⏸ ⏭); the labels become tooltips
    property bool actionIcons: false
    // The role "files" of Maia.Notifications.Center
    property var files: []
    property bool hasDefaultAction: false
    property bool inlineReply: false
    property string replyPlaceholder
    property string replySubmitText
    // NotificationCenter.Urgency: 2 = critical (a red edge)
    property int urgency: 0
    property string originName
    // A popup shows at most two lines of text; the center the whole text on demand
    property int maximumLineCount: 4
    readonly property bool hovered: hover.hovered
    // The answer field is open: the window needs the keyboard meanwhile
    readonly property bool replying: replyRow.visible
    // A file is being dragged out (a popup must not end meanwhile)
    readonly property bool dragging: filesView.dragging

    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string key)
    signal replied(string text)
    // One of its files (or their folder) was opened
    signal fileOpened(string url)

    implicitHeight: content.implicitHeight + 2 * Theme.spacingM
    border.color: card.urgency === 2 ? Theme.critical : Theme.stroke

    HoverHandler {
        id: hover
    }

    TapHandler {
        enabled: card.hasDefaultAction
        cursorShape: card.hasDefaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onTapped: card.defaultInvoked()
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingXS

        // --- Application, time, close ---

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            Item {
                implicitWidth: 16
                implicitHeight: 16

                // A file (a sender's own picture as its icon)
                Image {
                    anchors.fill: parent
                    visible: card.iconName.startsWith("file:")
                    source: visible ? card.iconName : ""
                    sourceSize: Qt.size(32, 32)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }

                LIcon {
                    anchors.fill: parent
                    visible: !card.iconName.startsWith("file:")
                    size: 16
                    // An icon the shell ships (tinted), or the application's icon from the theme
                    iconName: card.iconName.length > 0 ? card.iconName
                              : card.desktopEntry.length > 0 ? card.desktopEntry : "notification-active-symbolic"
                    tinted: iconName.endsWith("-symbolic")
                }
            }

            LText {
                Layout.fillWidth: true
                text: card.originName.length > 0 ? qsTr("%1 · %2").arg(card.appName).arg(card.originName) : card.appName
                elide: Text.ElideRight
                font.pixelSize: Theme.fontCaption
                color: Theme.textSecondary
            }

            LText {
                text: {
                    // Shell.now: once a minute, so "now" becomes the time
                    const minutes = (Shell.now.getTime() - card.time.getTime()) / 60000
                    return minutes < 1 ? qsTr("now") : Qt.formatTime(card.time, Qt.locale().timeFormat(Locale.ShortFormat))
                }
                font.pixelSize: Theme.fontCaption
                color: Theme.textTertiary
                visible: !card.hovered
            }

            SubtleButton {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                padding: 0
                visible: card.hovered
                Accessible.name: qsTr("Dismiss notification")
                contentItem: Item { LIcon { anchors.centerIn: parent; size: 12; iconName: "window-close-symbolic" } }
                onClicked: card.dismissed()
            }
        }

        // --- Title, text, picture ---

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingM

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 2

                LText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: card.title
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                LText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: card.body
                    textFormat: Text.StyledText
                    color: Theme.textSecondary
                    linkColor: Theme.accent
                    wrapMode: Text.Wrap
                    maximumLineCount: card.maximumLineCount
                    elide: Text.ElideRight
                    onLinkActivated: link => Qt.openUrlExternally(link)

                    HoverHandler {
                        cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }

            // Decoded in the image loader thread at its shown size, never on the GUI thread
            Image {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                Layout.alignment: Qt.AlignTop
                visible: card.image.length > 0 && status !== Image.Error
                source: card.image
                sourceSize: Qt.size(144, 144)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                clip: true
            }
        }

        // --- Files ---

        NotificationFiles {
            id: filesView

            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXS
            model: card.files
            onOpened: url => card.fileOpened(url)
        }

        // --- Actions ---

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingXS
            visible: card.actions.length > 0 || card.inlineReply
            spacing: Theme.spacingS

            Repeater {
                model: card.actions

                SubtleButton {
                    id: actionButton

                    required property var modelData

                    objectName: "action:" + actionButton.modelData.key

                    // With actionIcons: Lumen's glyph of the key (ActionGlyphs.js), else the icon
                    // theme's, else the label (an icon nobody has)
                    readonly property string glyphName: card.actionIcons ? ActionGlyphs.glyph(actionButton.modelData.key) : ""
                    readonly property bool showsIcon: card.actionIcons
                                                      && (glyphName.length > 0 ? glyph.status === Image.Ready : themeIcon.status === Image.Ready)

                    leftPadding: showsIcon ? Theme.spacingS : Theme.spacingM
                    rightPadding: showsIcon ? Theme.spacingS : Theme.spacingM
                    Accessible.name: actionButton.modelData.label
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: actionButton.pressed ? Theme.subtlePressed : actionButton.hovered ? Theme.subtleHover : Theme.control
                        border.width: 1
                        border.color: Theme.stroke
                    }
                    contentItem: Item {
                        implicitWidth: actionButton.showsIcon ? 16 : label.implicitWidth
                        implicitHeight: Math.max(16, label.implicitHeight)

                        LIcon {
                            id: glyph
                            anchors.centerIn: parent
                            visible: actionButton.showsIcon && actionButton.glyphName.length > 0
                            size: 16
                            iconName: actionButton.glyphName
                        }

                        LIcon {
                            id: themeIcon
                            anchors.centerIn: parent
                            visible: actionButton.showsIcon && actionButton.glyphName.length === 0
                            size: 16
                            tinted: false
                            iconName: card.actionIcons && actionButton.glyphName.length === 0 ? actionButton.modelData.key : ""
                        }

                        LText {
                            id: label
                            anchors.centerIn: parent
                            visible: !actionButton.showsIcon
                            text: actionButton.modelData.label
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                    onClicked: card.actionInvoked(actionButton.modelData.key)

                    LToolTip { text: actionButton.showsIcon ? actionButton.modelData.label : "" }
                }
            }

            SubtleButton {
                id: replyButton

                visible: card.inlineReply && !replyRow.visible
                leftPadding: Theme.spacingM
                rightPadding: Theme.spacingM
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: replyButton.pressed ? Theme.subtlePressed : replyButton.hovered ? Theme.subtleHover : Theme.control
                    border.width: 1
                    border.color: Theme.stroke
                }
                contentItem: LText { text: qsTr("Reply"); font.pixelSize: Theme.fontCaption }
                onClicked: {
                    replyRow.visible = true
                    replyField.forceActiveFocus()
                }
            }
        }

        // --- Answer field ---

        RowLayout {
            id: replyRow

            Layout.fillWidth: true
            visible: false
            spacing: Theme.spacingS

            PasswordField {
                id: replyField

                Layout.fillWidth: true
                hidden: false
                placeholderText: card.replyPlaceholder.length > 0 ? card.replyPlaceholder : qsTr("Type a reply…")
                onAccepted: send()

                function send() {
                    if (text.trim().length === 0)
                        return
                    card.replied(text)
                    text = ""
                }
            }

            AccentButton {
                text: card.replySubmitText.length > 0 ? card.replySubmitText : qsTr("Send")
                enabled: replyField.text.trim().length > 0
                onClicked: replyField.send()
            }
        }
    }
}
