import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts

import LumenFrontend

// Maia Settings: navigation at the left, the page with its sub-pages at the right.
Window {
    id: window

    // From the command line (main.cpp)
    property string initialPage
    property string testAction

    property string currentPageId

    width: 1100
    height: 720
    minimumWidth: 820
    minimumHeight: 480
    visible: true
    title: stack.currentItem && stack.currentItem.title ? stack.currentItem.title + " – " + qsTr("Maia Settings") : qsTr("Maia Settings")
    color: Theme.windowChrome

    // Called by main.cpp when another start asks for a page
    function activate(pageId) {
        if (pageId && pageId.length > 0)
            openPage(pageId)
        window.raise()
        window.requestActivate()
    }

    function openPage(pageId) {
        const row = Pages.indexOf(pageId)
        if (row < 0)
            return false
        if (pageId === currentPageId && stack.depth > 0) {
            stack.pop(null)
            return true
        }
        currentPageId = pageId
        stack.clear(Controls.StackView.Immediate)
        stack.push(Pages.get(row).source, {}, Controls.StackView.Immediate)
        return true
    }

    Component.onCompleted: {
        SettingsApp.testAction = testAction
        if (!(initialPage && openPage(initialPage)) && Pages.count > 0)
            openPage(Pages.get(0).pageId)
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: navigation.focusSearch()
    }

    Shortcut {
        sequences: [StandardKey.Back, "Alt+Left", "Esc"]
        enabled: stack.depth > 1
        onActivated: stack.pop()
    }

    Connections {
        target: SettingsApp

        function onPushRequested(source, properties) {
            stack.push(source, properties)
        }

        function onPopRequested() {
            if (stack.depth > 1)
                stack.pop()
        }

        function onToastRequested(text, actionText, onAction, onDismissed) {
            toast.show(text, actionText, onAction, onDismissed)
        }

        function onToastDismissRequested() {
            toast.finish(false)
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        NavigationPane {
            id: navigation

            currentPageId: window.currentPageId
            Layout.preferredWidth: 300
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.margins: Theme.spacingM
            onPageSelected: pageId => window.openPage(pageId)
        }

        // The content area: the "mica" frame around it, a lighter surface for the page
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingL

            PageHeader {
                id: header

                titles: {
                    const list = []
                    for (let i = 0; i < stack.depth; ++i) {
                        const item = stack.get(i, Controls.StackView.DontLoad)
                        list.push(item && item.title ? item.title : "")
                    }
                    return list
                }
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXL
                Layout.rightMargin: Theme.spacingXL
                Layout.topMargin: Theme.spacingXL
                onCrumbClicked: index => stack.pop(stack.get(index))
            }

            Controls.StackView {
                id: stack

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // A sub-page comes from the right and the page moves a little behind it (direction
                // tells where one is); going back reverses it
                pushEnter: Transition {
                    NumberAnimation { property: "x"; from: 40; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
                }
                pushExit: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
                }
                popEnter: Transition {
                    NumberAnimation { property: "x"; from: -40; to: 0; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal; easing.type: Theme.easingEnter }
                }
                popExit: Transition {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
                }
            }
        }
    }

    Toast {
        id: toast

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingXL
    }

    LText {
        anchors.centerIn: parent
        visible: Pages.count === 0
        text: qsTr("No settings pages are installed.")
        color: Theme.textSecondary
    }
}
