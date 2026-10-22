import QtQuick
import QtMultimedia

// Alarm sound of the kitchen timer. It is loaded by a Loader, so the timer keeps working
// without sound when the QtMultimedia module or the sound file is missing.
Item {
    id: sound

    // Freedesktop sound theme (package sound-theme-freedesktop)
    property url source: "file:///usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    property real volume: 0.8
    // The alarm stops by itself after this time, when nobody dismisses it
    property int maximumDuration: 60 * 1000

    function play() {
        player.stop()
        player.play()
        limit.restart()
    }

    function stop() {
        limit.stop()
        player.stop()
    }

    MediaPlayer {
        id: player

        source: sound.source
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {
            volume: sound.volume
        }

        onErrorOccurred: (error, errorString) => console.log("[Lumen] timer sound:", errorString)
    }

    Timer {
        id: limit

        interval: sound.maximumDuration
        onTriggered: player.stop()
    }
}
