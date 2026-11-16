import QtQuick
import QtTest

import LumenFrontend

// NotificationFiles and NotificationCard's actions, on their own: what is shown for the files of a
// notification, that a click opens a file and a gone one does nothing, and icon actions with their
// fallback to the label.
Item {
    id: root

    width: 420
    height: 700

    function file(name, extra) {
        const f = { url: "file:///tmp/" + name, name: name, mimeType: "application/octet-stream",
                    iconName: "application-octet-stream", genericIconName: "text-x-generic",
                    preview: "", local: true, exists: true, image: false }
        for (const key in extra)
            f[key] = extra[key]
        return f
    }

    function visibleChildren(item, name) {
        const found = []
        for (let i = 0; i < item.children.length; ++i) {
            const child = item.children[i]
            if (child.objectName === name && child.visible)
                found.push(child)
        }
        return found
    }

    NotificationFiles {
        id: files

        width: 360
    }

    SignalSpy {
        id: opened

        target: files
        signalName: "opened"
    }

    NotificationCard {
        id: card

        y: 360
        width: 360
        title: "Now playing"
        actionIcons: true
        actions: [{ key: "media-playback-pause", label: "Pause" }, { key: "no-such-icon-for-maia", label: "Like" }]
    }

    SignalSpy {
        id: invoked

        target: card
        signalName: "actionInvoked"
    }

    TestCase {
        name: "NotificationFiles"
        when: windowShown

        function init() {
            opened.clear()
            invoked.clear()
        }

        function test_one_file_with_a_preview_is_large() {
            files.model = [root.file("shot.png", { image: true, preview: "file:///tmp/shot.png" })]
            verify(files.large)
            compare(root.visibleChildren(files, "filePreview").length, 1)
            compare(root.visibleChildren(files, "fileRow").length, 0)
        }

        function test_files_without_a_preview_are_rows_at_most_three() {
            files.model = ["a.pdf", "b.txt", "c.odt", "d.mkv", "e.zip"].map(n => root.file(n))
            verify(!files.large)
            tryCompare(root.visibleChildren(files, "fileRow"), "length", 3)
            const more = root.visibleChildren(files, "moreFiles")
            compare(more.length, 1)
            compare(more[0].text, "and 2 more")
        }

        function test_a_click_opens_a_file_and_a_gone_one_does_nothing() {
            files.model = [root.file("report.pdf"), root.file("gone.txt", { exists: false })]
            let rows = []
            tryVerify(() => (rows = root.visibleChildren(files, "fileRow")).length === 2)
            waitForRendering(files)
            mouseClick(rows[0])
            compare(opened.count, 1)
            compare(opened.signalArguments[0][0], "file:///tmp/report.pdf")
            mouseClick(rows[1])
            compare(opened.count, 1)
            verify(rows[1].opacity < 1)
        }

        function test_icon_actions_show_an_icon_or_else_the_label() {
            const pause = findChild(card, "action:media-playback-pause")
            const like = findChild(card, "action:no-such-icon-for-maia")
            verify(pause && like)
            tryVerify(() => pause.showsIcon)
            verify(!like.showsIcon)
            waitForRendering(card)
            mouseClick(pause)
            compare(invoked.count, 1)
            compare(invoked.signalArguments[0][0], "media-playback-pause")
        }
    }
}
