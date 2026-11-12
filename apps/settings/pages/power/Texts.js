.pragma library

// Wording shared by the Power page: battery states, times, device kinds, profiles.
// The enumerations are those of Maia.Power (Power.*), passed in as numbers.

// Seconds -> "2 h 15 min", "45 min"; "" when unknown
function duration(seconds) {
    if (!(seconds > 0))
        return ""
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.round((seconds % 3600) / 60)
    if (hours > 0)
        return minutes > 0 ? qsTr("%1 h %2 min").arg(hours).arg(minutes) : qsTr("%1 h").arg(hours)
    return qsTr("%1 min").arg(Math.max(1, minutes))
}

// The state of a battery as GNOME says it: what happens and for how long
// state: Power.BatteryState (0 unknown, 1 charging, 2 discharging, 3 empty, 4 full, 5 pending charge,
// 6 pending discharge)
function batteryState(state, timeToEmpty, timeToFull) {
    switch (state) {
    case 1: {
        const left = duration(timeToFull)
        return left.length > 0 ? qsTr("Charging, %1 until full").arg(left) : qsTr("Charging")
    }
    case 2: {
        const left = duration(timeToEmpty)
        return left.length > 0 ? qsTr("%1 remaining").arg(left) : qsTr("On battery")
    }
    case 3: return qsTr("Empty")
    case 4: return qsTr("Fully charged")
    case 5: return qsTr("Plugged in, not charging")
    case 6: return qsTr("Waiting to discharge")
    }
    return qsTr("Unknown state")
}

// A Breeze battery glyph shipped with the frontend (assets/icons)
function batteryIcon(percentage, state) {
    if (state === 4)
        return "battery-full-charged-symbolic"
    const level = Math.max(0, Math.min(100, Math.round(percentage / 10) * 10))
    const charging = state === 1 || state === 5
    return "battery-" + ("00" + level).slice(-3) + (charging ? "-charging" : "") + "-symbolic"
}

// Power.DeviceKind -> a glyph (assets/icons)
function deviceIcon(kind) {
    switch (kind) {
    case 1: return "battery-ups-symbolic"           // UPS
    case 2: return "input-mouse-symbolic"
    case 3: return "input-keyboard-symbolic"
    case 4: return "input-touchpad-symbolic"
    case 6: return "input-tablet-symbolic"          // pen
    case 7: return "audio-headset-symbolic"
    case 8: return "audio-headphones-symbolic"
    case 9: return "speaker-symbolic"
    case 10: return "phone-symbolic"
    case 11: return "input-tablet-symbolic"
    case 13: return "computer-symbolic"
    }
    return "battery-080-symbolic"
}

// Power.DeviceKind -> its name, for a device that does not tell its own
function deviceKind(kind) {
    switch (kind) {
    case 0: return qsTr("Battery")
    case 1: return qsTr("Uninterruptible power supply")
    case 2: return qsTr("Mouse")
    case 3: return qsTr("Keyboard")
    case 4: return qsTr("Touchpad")
    case 5: return qsTr("Game controller")
    case 6: return qsTr("Pen")
    case 7: return qsTr("Headset")
    case 8: return qsTr("Headphones")
    case 9: return qsTr("Speakers")
    case 10: return qsTr("Phone")
    case 11: return qsTr("Tablet")
    case 12: return qsTr("Media player")
    case 13: return qsTr("Computer")
    case 14: return qsTr("Wearable")
    }
    return qsTr("Device")
}

// Power.Profile -> name, description (GNOME's wording), glyph
function profileName(profile) {
    switch (profile) {
    case 0: return qsTr("Power Saver")
    case 1: return qsTr("Balanced")
    case 2: return qsTr("Performance")
    }
    return ""
}

function profileDescription(profile) {
    switch (profile) {
    case 0: return qsTr("Reduced performance and power usage")
    case 1: return qsTr("Standard performance and power usage")
    case 2: return qsTr("High performance and power usage")
    }
    return ""
}

function profileIcon(profile) {
    switch (profile) {
    case 0: return "battery-profile-powersave-symbolic"
    case 1: return "battery-profile-balanced-symbolic"
    case 2: return "battery-profile-performance-symbolic"
    }
    return ""
}

// Power.Degradation -> why the performance mode is limited
function degradation(degraded) {
    switch (degraded) {
    case 1: return qsTr("The computer is on a lap. Performance is reduced to keep it from getting too hot.")
    case 2: return qsTr("The computer is too hot. Performance is reduced until it cools down.")
    case 3: return qsTr("Performance is reduced for now.")
    }
    return ""
}
