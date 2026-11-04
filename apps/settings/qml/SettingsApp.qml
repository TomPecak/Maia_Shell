pragma Singleton

import QtQuick

// What a page can ask of the frame: sub-pages, messages, the window.
//
//   SettingsApp.push(Qt.resolvedUrl("SavedNetworksPage.qml"), { deviceId: id })
//   SettingsApp.toast(qsTr("Network forgotten"), qsTr("Undo"), () => undo(), () => forgetNow())
QtObject {
    // Set by Main.qml: a run-time test action ("hidden", "hotspot", ...) for screenshots
    property string testAction

    signal pushRequested(url source, var properties)
    signal popRequested()
    signal toastRequested(string text, string actionText, var onAction, var onDismissed)
    signal toastDismissRequested()

    // Opens a sub-page of the current page (breadcrumb: "Wi-Fi › Saved networks")
    function push(source, properties) {
        pushRequested(source, properties || {})
    }

    function pop() {
        popRequested()
    }

    // A short message at the bottom with an optional action (e.g. Undo); onDismissed runs when
    // it goes away without the action (or another message replaces it)
    function toast(text, actionText, onAction, onDismissed) {
        toastRequested(text, actionText || "", onAction || null, onDismissed || null)
    }

    // Ends the message now as if it went away by itself (its onDismissed runs)
    function dismissToast() {
        toastDismissRequested()
    }
}
