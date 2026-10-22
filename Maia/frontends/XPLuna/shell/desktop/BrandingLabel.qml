import QtQuick

// "Maia Shell" label on the desktop, fades in a few seconds after start

Text {
    id: maiaText
    text: "Maia Shell"
    font.family: "NeverMind Handwriting"
    font.pointSize: 24
    color: "#FFFFFF"
    opacity: 0  // Start with fully transparent

    // Timer to trigger the animation after 5 seconds
    Timer {
        id: fadeInTimer
        interval: 3000  // 5 seconds delay
        running: true
        repeat: false
        onTriggered: {
            fadeInAnimation.start()
        }
    }

    // Animation to fade in the text
    NumberAnimation {
        id: fadeInAnimation
        target: maiaText
        property: "opacity"
        from: 0
        to: 0.7  // Target opacity
        duration: 1000  // Duration of the fade-in effect (1 second)
        easing.type: Easing.InOutQuad  // Smooth easing curve
    }
}
