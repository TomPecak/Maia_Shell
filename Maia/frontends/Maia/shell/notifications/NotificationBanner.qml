pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.kirigami.primitives as Primitives

import MaiaFrontend

import "ActionGlyphs.js" as ActionGlyphs

// A notification as a banner at the top of the screen, as on iPadOS. Compact: the application, the
// title and two lines of text. Expanded: the whole text, the picture, the files, the actions and an
// answer field.
//
//   tap             the default action (without one: expands)
//   swipe up        away; the notification stays in the list
//   pull down,
//   long press      expands
//   the chevron     the same for a mouse, which has no gestures to discover
//   the cross       (under a pointer, or expanded) the notification is deleted
//
// Only shows data and says what was asked: BannerWindow.qml talks to the notification center.
//
// Performance: the banner moves on the render thread (Animators on `mover`), so its movement does
// not depend on the GUI thread; the root item never moves, so the input mask of the window does
// not change while it does. What only an expanded banner shows is created ahead, in slices between
// frames (an asynchronous Loader), so that expanding never waits for it.
Item {
    id: banner

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
    // How many notifications wait behind this one
    property int waiting: 0
    // The window has its first frame: the banner may come in (so that no frame of it is lost)
    property bool ready: true
    // Longest the expanded text gets before it scrolls
    property int maximumBodyHeight: 220

    readonly property bool critical: urgency === 2
    // A critical one shows at once what can be done about it
    property bool expanded: critical && actions.length > 0
    readonly property bool replying: replyOpen
    readonly property bool leaving: d.leaving
    // Something more to see when expanded
    readonly property bool hasExtras: files.length > 0 || actions.length > 0 || inlineReply || image.length > 0
    readonly property bool canExpand: expanded || titleText.truncated || bodyText.truncated || hasExtras
    // The surface must accept the keyboard before the click on the answer field: a compositor gives
    // it on a press. Never for a banner the user has not come to (it would take the keyboard away
    // from the program being typed in)
    readonly property bool wantsKeyboard: replyOpen || (inlineReply && expanded && (d.expandedByUser || hover.hovered))
    // The user is busy with it: its time stands still
    readonly property bool held: hover.hovered || tap.pressed || swipe.active || expanded || replying
                                 || (extras.item !== null && extras.item.dragging)
    property bool replyOpen: false

    signal swipedAway()
    signal dismissed()
    signal defaultInvoked()
    signal actionInvoked(string key)
    signal replied(string text)
    signal fileOpened(string url)
    // The way out has ended (leave())
    signal leaveFinished()

    // Out, on the render thread. replaced: another banner comes in its place, so this one sinks
    // behind it instead of crossing it on the way up
    function leave(replaced) {
        if (d.leaving)
            return
        d.leaving = true
        enter.stop()
        snapBack.stop()
        if (!d.entered) {
            banner.leaveFinished()
            return
        }
        if (replaced)
            sink.start()
        else
            rise.start()
    }

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

    implicitHeight: d.targetHeight
    height: implicitHeight

    // Monochrome icons (of an application, of a file) in the text color of the mode
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: Theme.label

    Accessible.role: Accessible.AlertMessage
    Accessible.name: banner.title
    Accessible.description: banner.body

    onReadyChanged: d.comeIn()
    Component.onCompleted: d.comeIn()

    QtObject {
        id: d

        property bool leaving: false
        property bool entered: false
        property bool expandedByUser: false
        readonly property int padding: 14
        readonly property int iconSize: 38
        readonly property int offScreen: mover.height + 24
        // A swipe this far goes away, whatever the banner's height: it starts near the top edge
        // of the screen, so there is little room for the finger or the pointer
        readonly property int swipeAway: 32
        // A pull this far (after its resistance) expands
        readonly property int expandPull: 30
        readonly property int compactHeight: head.height + 2 * padding
        readonly property int fullHeight: content.implicitHeight + 2 * padding
        readonly property int targetHeight: banner.expanded ? fullHeight : compactHeight

        function comeIn() {
            if (!banner.ready || entered || leaving)
                return
            entered = true
            enter.start()
        }

        function focusReply() {
            if (!extras.item || !banner.replyOpen)
                return
            const window = banner.Window.window
            if (window)
                window.requestActivate()
            extras.item.focusReply()
        }

        // Up follows the finger, down resists: a banner has nowhere to go there
        function pulled(distance) {
            return distance < 0 ? distance : Math.min(distance * 0.4, 48)
        }

        function released(velocity) {
            const distance = mover.y
            if (distance < -d.swipeAway || (velocity < -400 && distance < -8)) {
                banner.swipedAway()
                return
            }
            if (distance >= expandPull && !banner.expanded)
                banner.setExpanded(true)
            snapBack.start()
        }
    }

    // --- What moves: the plate and its shadow together ---

    Item {
        id: mover

        width: banner.width
        height: d.targetHeight
        opacity: 0
        scale: tap.pressed && !swipe.active ? 0.98 : 1

        Behavior on height {
            enabled: d.entered && !d.leaving

            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            ScaleAnimator { duration: 120; easing.type: Easing.OutCubic }
        }

        RectangularShadow {
            anchors.fill: plate
            offset.y: 6
            blur: 24
            radius: plate.radius
            color: Theme.shadow
        }

        Rectangle {
            id: plate

            objectName: "bannerPlate"
            anchors.fill: parent
            radius: 22
            color: Theme.card
            border.width: banner.critical ? 2 : 1
            border.color: banner.critical ? Theme.red : Theme.hairline
            clip: true

            HoverHandler {
                id: hover
            }

            TapHandler {
                id: tap

                longPressThreshold: 0.45
                enabled: !banner.leaving
                cursorShape: Qt.PointingHandCursor
                onTapped: {
                    if (banner.hasDefaultAction)
                        banner.defaultInvoked()
                    else if (banner.canExpand && !banner.expanded)
                        banner.setExpanded(true)
                }
                onLongPressed: {
                    if (banner.canExpand)
                        banner.setExpanded(true)
                }
            }

            DragHandler {
                id: swipe

                target: null
                xAxis.enabled: false
                enabled: !banner.leaving && !banner.replying
                onActiveChanged: {
                    if (active) {
                        enter.complete()
                        snapBack.stop()
                    } else {
                        d.released(centroid.velocity.y)
                    }
                }
                onActiveTranslationChanged: {
                    if (active)
                        mover.y = d.pulled(activeTranslation.y)
                }
            }

            Column {
                id: content

                x: d.padding
                y: d.padding
                width: plate.width - 2 * d.padding
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
                            visible: banner.appIcon.startsWith("file:")
                            source: visible ? banner.appIcon : ""
                            sourceSize: Qt.size(76, 76)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }

                        Kirigami.Icon {
                            anchors.fill: parent
                            visible: !banner.appIcon.startsWith("file:")
                            roundToIconSize: false
                            source: banner.appIcon.length > 0 ? banner.appIcon
                                  : banner.desktopEntry.length > 0 ? banner.desktopEntry
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
                            objectName: "bannerMeta"
                            width: parent.width - buttons.width
                            text: {
                                const parts = [banner.appName]
                                if (banner.originName.length > 0)
                                    parts.push(banner.originName)
                                const minutes = (Date.now() - banner.time.getTime()) / 60000
                                parts.push(banner.expanded || minutes >= 1
                                           ? Qt.formatTime(banner.time, Qt.locale().timeFormat(Locale.ShortFormat))
                                           : qsTr("now"))
                                if (banner.waiting > 0)
                                    parts.push(qsTr("%1 more").arg(banner.waiting))
                                return parts.join(" · ")
                            }
                            elide: Text.ElideRight
                            color: Theme.secondaryLabel
                            font.pixelSize: 12
                        }

                        Text {
                            id: titleText

                            objectName: "bannerTitle"
                            width: parent.width
                            visible: text.length > 0
                            text: banner.title
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: banner.expanded ? 3 : 1
                            elide: Text.ElideRight
                            color: Theme.label
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Flickable {
                            id: bodyView

                            width: parent.width
                            height: banner.expanded ? Math.min(bodyText.implicitHeight, banner.maximumBodyHeight)
                                                    : bodyText.implicitHeight
                            visible: bodyText.text.length > 0
                            contentHeight: bodyText.implicitHeight
                            interactive: banner.expanded && contentHeight > height
                            clip: interactive
                            boundsBehavior: Flickable.StopAtBounds

                            Text {
                                id: bodyText

                                objectName: "bannerBody"
                                width: bodyView.width
                                text: banner.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: banner.expanded ? 1000 : 2
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
                        visible: banner.image.length > 0 && !banner.expanded
                        radius: 10
                        color: Theme.secondaryFill
                        source: banner.image
                        sourceSize: Qt.size(88, 88)
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                // --- Only when expanded ---

                Loader {
                    id: extras

                    width: content.width
                    active: banner.hasExtras
                    asynchronous: true
                    enabled: banner.expanded
                    // Drawn only while it can be seen; closing, it goes with the plate
                    visible: status === Loader.Ready && (banner.expanded || mover.height > d.compactHeight)
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

                BannerButton {
                    objectName: "expandButton"
                    visible: banner.canExpand && !(banner.critical && banner.actions.length > 0)
                    round: true
                    glyph: Qt.resolvedUrl("../../assets/icons/go-down-symbolic.svg")
                    text: banner.expanded ? qsTr("Show less") : qsTr("Show more")
                    rotation: banner.expanded ? 180 : 0
                    onClicked: banner.setExpanded(!banner.expanded)

                    Behavior on rotation {
                        RotationAnimator { duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                BannerButton {
                    objectName: "closeButton"
                    visible: hover.hovered || banner.expanded || banner.critical
                    round: true
                    glyph: Qt.resolvedUrl("../../assets/icons/window-close-symbolic.svg")
                    text: qsTr("Dismiss notification")
                    onClicked: banner.dismissed()
                }
            }
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
                objectName: "bannerImage"
                width: parent.width
                height: 168
                visible: banner.image.length > 0 && banner.files.length === 0
                radius: 14
                color: Theme.secondaryFill
                source: visible ? banner.image : ""
                sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }

            BannerFiles {
                id: filesView

                width: parent.width
                model: banner.files
                onOpenRequested: url => banner.fileOpened(url)
            }

            // A media player's keys: side by side, centered
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: banner.actionIcons && banner.actions.length > 0
                spacing: 8

                Repeater {
                    model: banner.actionIcons ? banner.actions : []

                    BannerButton {
                        id: iconAction

                        required property var modelData

                        readonly property string glyphName: ActionGlyphs.glyph(modelData.key)

                        objectName: "action:" + modelData.key
                        round: true
                        plateSize: 40
                        glyph: glyphName.length > 0 ? Qt.resolvedUrl("../../assets/icons/" + glyphName + ".svg") : ""
                        themeIcon: glyphName.length > 0 ? "" : modelData.key
                        text: modelData.label
                        onClicked: banner.actionInvoked(iconAction.modelData.key)
                    }
                }
            }

            // Text actions: two share a row, more get one each (long labels stay readable)
            Grid {
                id: actionGrid

                readonly property int shownColumns: banner.actions.length === 2 ? 2 : 1

                visible: !banner.actionIcons && banner.actions.length > 0
                columns: shownColumns
                columnSpacing: 8
                rowSpacing: 6

                Repeater {
                    model: banner.actionIcons ? [] : banner.actions

                    BannerButton {
                        id: textAction

                        required property var modelData

                        objectName: "action:" + modelData.key
                        width: (extrasColumn.width - (actionGrid.shownColumns - 1) * actionGrid.columnSpacing)
                               / actionGrid.shownColumns
                        text: modelData.label
                        onClicked: banner.actionInvoked(textAction.modelData.key)
                    }
                }
            }

            BannerButton {
                objectName: "replyButton"
                width: parent.width
                visible: banner.inlineReply && !banner.replyOpen
                text: qsTr("Reply")
                onClicked: banner.openReply()
            }

            BannerReplyField {
                id: replyField

                objectName: "replyField"
                width: parent.width
                visible: banner.replyOpen
                placeholderText: banner.replyPlaceholder
                submitText: banner.replySubmitText
                // Closed again: a sender that keeps its notification lets it end by its time
                onSent: text => {
                    banner.setExpanded(false)
                    banner.replied(text)
                }
                onCancelled: banner.replyOpen = false
            }
        }
    }

    // --- Movement, all of it on the render thread ---

    ParallelAnimation {
        id: enter

        YAnimator {
            target: mover
            from: -d.offScreen
            to: 0
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 0.7
        }
        OpacityAnimator {
            target: mover
            from: 0
            to: 1
            duration: 160
            easing.type: Easing.OutQuad
        }
    }

    YAnimator {
        id: snapBack

        target: mover
        to: 0
        duration: 260
        easing.type: Easing.OutBack
        easing.overshoot: 0.8
    }

    SequentialAnimation {
        id: rise

        ParallelAnimation {
            YAnimator {
                target: mover
                to: -d.offScreen
                duration: 220
                easing.type: Easing.InCubic
            }
            OpacityAnimator {
                target: mover
                to: 0
                duration: 220
                easing.type: Easing.InQuad
            }
        }
        ScriptAction {
            script: banner.leaveFinished()
        }
    }

    SequentialAnimation {
        id: sink

        ParallelAnimation {
            ScaleAnimator {
                target: mover
                to: 0.92
                duration: 200
                easing.type: Easing.OutCubic
            }
            OpacityAnimator {
                target: mover
                to: 0
                duration: 200
                easing.type: Easing.OutQuad
            }
        }
        ScriptAction {
            script: banner.leaveFinished()
        }
    }
}
