pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.kirigami.primitives as Primitives

import MaiaFrontend

import "ActionGlyphs.js" as ActionGlyphs

// A notification on its plate, the same in a banner (NotificationBanner.qml) and in the notification
// center (NotificationRow.qml). Compact: the application, the title and two lines of text. Expanded:
// the whole text, the picture, the files, the actions and an answer field. The chevron expands (a
// mouse has no gestures to discover), the cross deletes.
//
// Only shows data and says what was asked. How it moves, and what a tap or a swipe does, is up to
// whoever holds it: gesture handlers can be declared inside it. It says how high it wants to be
// (targetHeight); the holder gives it that height, animated if it wants.
//
// What only an expanded card shows is created in slices between frames (an asynchronous Loader), so
// that expanding never waits for it.
Rectangle {
    id: card

    property string appName
    // A theme icon name or a file URL
    property string appIcon
    property string desktopEntry
    property string title
    // StyledText: <b> <i> <u> <a> <br/> (made safe by the service)
    property string body
    property date time
    property string image
    // [{ key, label }] without "default"
    property var actions: []
    // The keys are icon names (a media player's ⏮ ⏸ ⏭); the labels are for screen readers
    property bool actionIcons: false
    // The role "files" of Maia.Notifications.Center
    property var files: []
    property bool hasDefaultAction: false
    property bool inlineReply: false
    property string replyPlaceholder
    property string replySubmitText
    // NotificationCenter.Urgency: 2 = critical
    property int urgency: 0
    property string originName
    // How many more are behind this one (waiting, or folded into its stack)
    property int waiting: 0
    // Longest the expanded text gets before it scrolls
    property int maximumBodyHeight: 220
    // "5 min ago" against this moment, for a list that stays open; null: only "now" or the time
    property var now: null
    // Create the expanded part ahead (a banner); a list of many creates it when it is asked for
    property bool createExtrasAhead: true
    // Its cross may show (not while a holder shows another way to delete it)
    property bool closable: true

    readonly property bool critical: urgency === 2
    // A critical one shows at once what can be done about it
    property bool expanded: critical && actions.length > 0
    property bool replyOpen: false
    readonly property bool hovered: hover.hovered
    // A file is being dragged out of it
    readonly property bool dragging: extras.item !== null && extras.item.dragging
    // Something more to see when expanded
    readonly property bool hasExtras: files.length > 0 || actions.length > 0 || inlineReply || image.length > 0
    readonly property bool canExpand: expanded || titleText.truncated || bodyText.truncated || hasExtras
    // The surface must accept the keyboard before the click on the answer field: a compositor gives
    // it on a press. Never for a card the user has not come to (it would take the keyboard away
    // from the program being typed in)
    readonly property bool wantsKeyboard: replyOpen || (inlineReply && expanded && (d.expandedByUser || hover.hovered))

    readonly property int compactHeight: head.height + 2 * d.padding
    readonly property int fullHeight: content.implicitHeight + 2 * d.padding
    readonly property int targetHeight: expanded ? fullHeight : compactHeight

    signal dismissed()
    signal actionInvoked(string key)
    signal replied(string text)
    signal fileOpened(string url)

    function setExpanded(value) {
        if (value)
            d.expandedByUser = true
        expanded = value
        if (!value)
            replyOpen = false
    }

    function openReply() {
        setExpanded(true)
        replyOpen = true
        Qt.callLater(d.focusReply)
    }

    radius: 22
    color: Theme.card
    border.width: critical ? 2 : 1
    border.color: critical ? Theme.red : Theme.hairline
    clip: true

    // Monochrome icons (of an application, of a file) in the text color of the mode
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: Theme.label

    Accessible.role: Accessible.AlertMessage
    Accessible.name: card.title
    Accessible.description: card.body

    QtObject {
        id: d

        property bool expandedByUser: false
        readonly property int padding: 14
        readonly property int iconSize: 38

        function focusReply() {
            if (!extras.item || !card.replyOpen)
                return
            const window = card.Window.window
            if (window)
                window.requestActivate()
            extras.item.focusReply()
        }

        function timeText() {
            const reference = card.now ? card.now.getTime() : Date.now()
            const minutes = Math.floor((reference - card.time.getTime()) / 60000)
            const clock = Qt.formatTime(card.time, Qt.locale().timeFormat(Locale.ShortFormat))
            if (card.now === null)
                return card.expanded || minutes >= 1 ? clock : qsTr("now")
            if (minutes < 1)
                return qsTr("now")
            if (minutes < 60)
                return qsTr("%1 min ago").arg(minutes)
            const sameDay = new Date(reference).toDateString() === card.time.toDateString()
            return sameDay ? clock : Qt.formatDate(card.time, Qt.locale().dateFormat(Locale.ShortFormat)) + " " + clock
        }
    }

    HoverHandler {
        id: hover
    }

    Column {
        id: content

        x: d.padding
        y: d.padding
        width: card.width - 2 * d.padding
        spacing: 12

        // --- The application, the title, the text ---

        Item {
            id: head

            width: content.width
            height: Math.max(d.iconSize, texts.implicitHeight)

            Item {
                id: icon

                width: d.iconSize
                height: d.iconSize

                // A file (a sender's own picture as its icon)
                Image {
                    anchors.fill: parent
                    visible: card.appIcon.startsWith("file:")
                    source: visible ? card.appIcon : ""
                    sourceSize: Qt.size(76, 76)
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }

                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !card.appIcon.startsWith("file:")
                    roundToIconSize: false
                    source: card.appIcon.length > 0 ? card.appIcon
                          : card.desktopEntry.length > 0 ? card.desktopEntry
                          : "preferences-desktop-notification"
                    fallback: "application-x-executable"
                }
            }

            Column {
                id: texts

                anchors.left: icon.right
                anchors.leftMargin: 12
                anchors.right: thumbnail.visible ? thumbnail.left : parent.right
                anchors.rightMargin: thumbnail.visible ? 10 : 0
                spacing: 1

                Text {
                    objectName: "cardMeta"
                    width: parent.width - buttons.width
                    text: {
                        const parts = [card.appName]
                        if (card.originName.length > 0)
                            parts.push(card.originName)
                        parts.push(d.timeText())
                        if (card.waiting > 0)
                            parts.push(qsTr("%1 more").arg(card.waiting))
                        return parts.join(" · ")
                    }
                    elide: Text.ElideRight
                    color: Theme.secondaryLabel
                    font.pixelSize: 12
                }

                Text {
                    id: titleText

                    objectName: "cardTitle"
                    width: parent.width
                    visible: text.length > 0
                    text: card.title
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: card.expanded ? 3 : 1
                    elide: Text.ElideRight
                    color: Theme.label
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Flickable {
                    id: bodyView

                    width: parent.width
                    height: card.expanded ? Math.min(bodyText.implicitHeight, card.maximumBodyHeight)
                                          : bodyText.implicitHeight
                    visible: bodyText.text.length > 0
                    contentHeight: bodyText.implicitHeight
                    interactive: card.expanded && contentHeight > height
                    clip: interactive
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: bodyText

                        objectName: "cardBody"
                        width: bodyView.width
                        text: card.body
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: card.expanded ? 1000 : 2
                        elide: Text.ElideRight
                        color: Theme.secondaryLabel
                        linkColor: Theme.accent
                        font.pixelSize: 14
                        onLinkActivated: link => Qt.openUrlExternally(link)

                        HoverHandler {
                            cursorShape: bodyText.hoveredLink.length > 0 ? Qt.PointingHandCursor
                                                                         : undefined
                        }
                    }
                }
            }

            // The picture beside the text; expanded it is shown large below
            Primitives.ShadowedImage {
                id: thumbnail

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 44
                height: 44
                visible: card.image.length > 0 && !card.expanded
                radius: 10
                color: Theme.secondaryFill
                source: card.image
                sourceSize: Qt.size(88, 88)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }
        }

        // --- Only when expanded ---

        Loader {
            id: extras

            width: content.width
            active: card.hasExtras && (card.createExtrasAhead || card.expanded || item !== null)
            asynchronous: true
            enabled: card.expanded
            // Drawn only while it can be seen; closing, it goes with the plate
            visible: status === Loader.Ready && (card.expanded || card.height > card.compactHeight)
            sourceComponent: extrasComponent
            onLoaded: d.focusReply()
        }
    }

    // --- Expand and close: in the corner, under the finger of a hand holding the tablet ---

    Row {
        id: buttons

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.rightMargin: 3
        layoutDirection: Qt.RightToLeft

        NotificationButton {
            objectName: "expandButton"
            visible: card.canExpand && !(card.critical && card.actions.length > 0)
            round: true
            glyph: Qt.resolvedUrl("../../assets/icons/go-down-symbolic.svg")
            text: card.expanded ? qsTr("Show less") : qsTr("Show more")
            rotation: card.expanded ? 180 : 0
            onClicked: card.setExpanded(!card.expanded)

            Behavior on rotation {
                RotationAnimator { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        NotificationButton {
            objectName: "closeButton"
            visible: card.closable && (hover.hovered || card.expanded || card.critical)
            round: true
            glyph: Qt.resolvedUrl("../../assets/icons/window-close-symbolic.svg")
            text: qsTr("Dismiss notification")
            onClicked: card.dismissed()
        }
    }

    Component {
        id: extrasComponent

        Column {
            id: extrasColumn

            readonly property bool dragging: filesView.dragging

            function focusReply() {
                replyField.input.forceActiveFocus()
            }

            spacing: 10

            Primitives.ShadowedImage {
                objectName: "cardImage"
                width: parent.width
                height: 168
                visible: card.image.length > 0 && card.files.length === 0
                radius: 14
                color: Theme.secondaryFill
                source: visible ? card.image : ""
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }

            NotificationFiles {
                id: filesView

                width: parent.width
                model: card.files
                onOpenRequested: url => card.fileOpened(url)
            }

            // A media player's keys: side by side, centered
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: card.actionIcons && card.actions.length > 0
                spacing: 8

                Repeater {
                    model: card.actionIcons ? card.actions : []

                    NotificationButton {
                        id: iconAction

                        required property var modelData

                        readonly property string glyphName: ActionGlyphs.glyph(modelData.key)

                        objectName: "action:" + modelData.key
                        round: true
                        plateSize: 40
                        glyph: glyphName.length > 0 ? Qt.resolvedUrl("../../assets/icons/" + glyphName + ".svg") : ""
                        themeIcon: glyphName.length > 0 ? "" : modelData.key
                        text: modelData.label
                        onClicked: card.actionInvoked(iconAction.modelData.key)
                    }
                }
            }

            // Text actions: two share a row, more get one each (long labels stay readable)
            Grid {
                id: actionGrid

                readonly property int shownColumns: card.actions.length === 2 ? 2 : 1

                visible: !card.actionIcons && card.actions.length > 0
                columns: shownColumns
                columnSpacing: 8
                rowSpacing: 6

                Repeater {
                    model: card.actionIcons ? [] : card.actions

                    NotificationButton {
                        id: textAction

                        required property var modelData

                        objectName: "action:" + modelData.key
                        width: (extrasColumn.width - (actionGrid.shownColumns - 1) * actionGrid.columnSpacing)
                               / actionGrid.shownColumns
                        text: modelData.label
                        onClicked: card.actionInvoked(textAction.modelData.key)
                    }
                }
            }

            NotificationButton {
                objectName: "replyButton"
                width: parent.width
                visible: card.inlineReply && !card.replyOpen
                text: qsTr("Reply")
                onClicked: card.openReply()
            }

            NotificationReplyField {
                id: replyField

                objectName: "replyField"
                width: parent.width
                visible: card.replyOpen
                placeholderText: card.replyPlaceholder
                submitText: card.replySubmitText
                // Closed again: a sender that keeps its notification lets it end by its time
                onSent: text => {
                    card.setExpanded(false)
                    card.replied(text)
                }
                onCancelled: card.replyOpen = false
            }
        }
    }
}
