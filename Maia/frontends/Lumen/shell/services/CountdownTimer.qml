import QtQuick
import QtCore

// Logic of the kitchen timer: a countdown with pause, adding time and an alarm state.
//
// The remaining time is computed from the end time, not by counting ticks, so the countdown
// does not drift when the GUI thread is busy. The last set duration is remembered.
QtObject {
    id: countdown

    // "idle", "running", "paused" or "finished"
    property string status: "idle"
    // Duration of the next countdown, ms
    property int duration: settings.lastDuration
    // Remaining time, ms
    property int remaining: duration
    // Length of the current countdown (with the added time), base of the progress
    property int total: duration
    // Moment the countdown ends, valid while running
    property double endTime: 0

    readonly property bool active: status === "running" || status === "paused"
    readonly property real fraction: total > 0 ? remaining / total : 0
    readonly property int minimumDuration: 10 * 1000
    readonly property int maximumDuration: 3 * 60 * 60 * 1000

    // Persisted user choices, also used by the window (collapsed state)
    property Settings settings: Settings {
        category: "LumenTimer"

        property int lastDuration: 5 * 60 * 1000
        property bool collapsed: false
    }

    // Emitted when the countdown reaches zero
    signal elapsed()

    function clampDuration(ms) {
        return Math.max(minimumDuration, Math.min(maximumDuration, ms))
    }

    // Sets the duration of the next countdown (in the idle state also the shown time)
    function setDuration(ms) {
        duration = clampDuration(ms)
        settings.lastDuration = duration
        if (status === "idle") {
            remaining = duration
            total = duration
        }
    }

    // Starts the countdown, optionally with a new duration
    function start(ms) {
        if (ms !== undefined)
            setDuration(ms)
        if (status === "idle" || status === "finished") {
            remaining = duration
            total = duration
        }
        run()
    }

    function pause() {
        if (status !== "running")
            return
        update()
        ticker.stop()
        status = "paused"
    }

    function resume() {
        if (status === "paused")
            run()
    }

    // Main action of the timer: start, pause / resume or dismiss the alarm
    function toggle() {
        if (status === "running")
            pause()
        else if (status === "paused")
            resume()
        else if (status === "finished")
            reset()
        else
            start()
    }

    function reset() {
        ticker.stop()
        remaining = duration
        total = duration
        status = "idle"
    }

    // Adds (or with a negative value removes) time. After the alarm it starts a new
    // countdown of the given length (snooze).
    function add(ms) {
        if (status === "idle") {
            setDuration(duration + ms)
        } else if (status === "finished") {
            if (ms <= 0)
                return
            remaining = ms
            total = ms
            run()
        } else {
            if (status === "running")
                update()
            remaining = Math.max(1000, Math.min(maximumDuration, remaining + ms))
            total = Math.max(remaining, total + ms)
            if (status === "running")
                endTime = Date.now() + remaining
        }
    }

    function run() {
        endTime = Date.now() + remaining
        status = "running"
        ticker.start()
    }

    function update() {
        remaining = Math.max(0, endTime - Date.now())
        if (remaining === 0 && status === "running") {
            ticker.stop()
            status = "finished"
            elapsed()
        }
    }

    // Formats a time in ms as m:ss or h:mm:ss, the seconds are rounded up
    function format(ms) {
        const seconds = Math.ceil(ms / 1000)
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        const s = seconds % 60
        const ss = (s < 10 ? "0" : "") + s
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
        return (m < 10 ? "0" : "") + m + ":" + ss
    }

    property Timer ticker: Timer {
        interval: 100
        repeat: true
        onTriggered: countdown.update()
    }
}
