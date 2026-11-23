import QtQuick

import "jobs"
import "notifications"

// The overlay layer of the shell, its own process: what has to be seen above everything, fullscreen
// windows included. The root window (which the server's MProxyWindow controls) is never shown; each
// surface of this layer is shown only while it has something on it, so that nothing lies over a
// fullscreen window in vain and the compositor can scan it out directly.
Window {
    id: root

    visible: false
    title: "overlay"

    BannerWindow {
        id: banners
    }

    // The job in progress; one thing at a time at the top, and a banner comes first
    JobPillWindow {
        covered: banners.visible
    }
}
