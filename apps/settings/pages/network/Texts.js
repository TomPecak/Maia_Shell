.pragma library

// Wording shared by the Wi-Fi page: device states, failure reasons, security types, bands, times.
// The enumerations are those of Maia.Network (Network.*), passed in as numbers.

// Network.StateReason -> what went wrong, said so that the user knows what to do
function reason(r) {
    switch (r) {
    case 2: return qsTr("A password is needed.")                                   // NoSecrets
    case 3: return qsTr("Wrong password?")                                          // WrongSecrets
    case 4: return qsTr("The network refused the connection.")                     // SupplicantFailed
    case 5: return qsTr("The network did not answer in time. Is it in reach?")    // SupplicantTimeout
    case 6: return qsTr("The connection settings are not valid.")                  // ConfigFailed
    case 7: return qsTr("No address from the network (DHCP).")                     // IpConfigFailed
    case 8: return qsTr("The network address expired.")                            // IpConfigExpired
    case 9: return qsTr("The connection was deleted.")                             // ConnectionRemoved
    case 10: return qsTr("The network is not in reach.")                           // SsidNotFound
    case 11: return qsTr("The Wi-Fi adapter's firmware is missing.")               // FirmwareMissing
    case 13: return qsTr("The connection was lost.")                               // CarrierLost
    default: return qsTr("The connection failed.")
    }
}

// Network.Security -> its usual name
function security(s) {
    switch (s) {
    case 0: return qsTr("None")
    case 1: return qsTr("Enhanced Open")
    case 2: return "WEP"
    case 3: return "LEAP"
    case 4: return qsTr("WPA & WPA2 Personal")
    case 5: return qsTr("WPA3 Personal")
    case 6: return qsTr("WPA & WPA2 Enterprise")
    case 7: return qsTr("WPA3 Enterprise")
    }
    return ""
}

// The security types offered for a new or edited profile (WEP only when the profile has it:
// it is broken, GNOME no longer offers it)
function securityChoices(current) {
    const list = [0, 1, 4, 5, 6, 7, 3]
    if (current === 2)
        list.push(2)
    return list.map(s => ({ text: security(s), value: s }))
}

function isPersonal(s) { return s === 4 || s === 5 }
function isEnterprise(s) { return s === 6 || s === 7 }

// 0..4 -> the icon of the signal level
function signalIcon(level) {
    return ["network-wireless-signal-none-symbolic", "network-wireless-signal-weak-symbolic",
            "network-wireless-signal-ok-symbolic", "network-wireless-signal-good-symbolic",
            "network-wireless-signal-excellent-symbolic"][Math.max(0, Math.min(4, level))]
}

function signalText(level) {
    return [qsTr("None"), qsTr("Weak"), qsTr("Ok"), qsTr("Good"), qsTr("Excellent")][Math.max(0, Math.min(4, level))]
}

// MHz -> "2.4 GHz", "5 GHz", "6 GHz"
function band(frequency) {
    if (frequency <= 0)
        return ""
    if (frequency < 3000)
        return qsTr("2.4 GHz")
    if (frequency < 5925)
        return qsTr("5 GHz")
    return qsTr("6 GHz")
}

// Network.Band bits -> "2.4 GHz, 5 GHz"
function bands(bits) {
    const list = []
    if (bits & 1) list.push(qsTr("2.4 GHz"))
    if (bits & 2) list.push(qsTr("5 GHz"))
    if (bits & 4) list.push(qsTr("6 GHz"))
    return list.join(", ")
}

// kbit/s -> "866 Mb/s"
function speed(kbits) {
    return kbits > 0 ? qsTr("%1 Mb/s").arg(Math.round(kbits / 1000)) : ""
}

// A Date (invalid = never) -> "Today", "Yesterday", "3 days ago", "Never"
function lastUsed(date) {
    if (!date || isNaN(date.getTime()))
        return qsTr("Never")
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const day = new Date(date.getTime())
    day.setHours(0, 0, 0, 0)
    const days = Math.round((today - day) / 86400000)
    if (days <= 0)
        return qsTr("Today")
    if (days === 1)
        return qsTr("Yesterday")
    return qsTr("%1 days ago").arg(days)
}

// "255.255.255.0" or "24" -> 24, -1 when neither
function prefixOf(text, ip6) {
    text = (text || "").trim()
    if (/^\d{1,3}$/.test(text)) {
        const n = parseInt(text)
        return n <= (ip6 ? 128 : 32) ? n : -1
    }
    if (ip6)
        return -1
    const parts = text.split(".")
    if (parts.length !== 4)
        return -1
    let bits = 0
    let ended = false
    for (const part of parts) {
        if (!/^\d{1,3}$/.test(part))
            return -1
        let n = parseInt(part)
        if (n > 255)
            return -1
        for (let b = 7; b >= 0; --b) {
            const set = (n >> b) & 1
            if (set && ended)
                return -1
            if (set) ++bits; else ended = true
        }
    }
    return bits
}

// "1.1.1.1, 9.9.9.9" -> ["1.1.1.1", "9.9.9.9"]
function list(text) {
    return (text || "").split(/[\s,;]+/).filter(s => s.length > 0)
}

// The checks of the password dialog (the same rules as the service and GNOME)
function validWpaPassword(text) {
    return (text.length >= 8 && text.length <= 63) || (text.length === 64 && /^[0-9a-fA-F]+$/.test(text))
}

function validWepKey(text, passphrase) {
    if (passphrase)
        return text.length >= 1 && text.length <= 64
    return text.length === 5 || text.length === 13 || ((text.length === 10 || text.length === 26) && /^[0-9a-fA-F]+$/.test(text))
}

// A control call's result -> a sentence for the user (the service's message stays in the log)
function error(result) {
    if (result.message)
        console.warn("[Wi-Fi]", result.message)
    switch (result.error) {
    case 1: return qsTr("The network or the Wi-Fi adapter is gone.")                         // NotFound
    case 2: return qsTr("Not allowed, or the authentication was cancelled.")                // NotAllowed
    case 3: return qsTr("Some of the details are not valid.")                               // InvalidArgument
    case 4: return qsTr("This Wi-Fi adapter does not support it.")                          // NotSupported
    case 5: return qsTr("Wi-Fi is not available right now.")                                // Unavailable
    default: return qsTr("NetworkManager refused it.")
    }
}

// A deep copy of settings from NetworkControl (the SSID's bytes included)
function clone(value) {
    if (value instanceof ArrayBuffer)
        return value.slice(0)
    // Lists from C++ may be array-like objects rather than arrays
    if (Array.isArray(value) || (value !== null && typeof value === "object" && typeof value.length === "number"))
        return Array.from(value).map(clone)
    if (value !== null && typeof value === "object") {
        const copy = {}
        for (const key in value)
            copy[key] = clone(value[key])
        return copy
    }
    return value
}

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}

// A file URL from a file dialog -> its path
function pathOf(url) {
    return decodeURIComponent(url.toString().replace(/^file:\/\//, ""))
}

// The length of a text in UTF-8 bytes (an SSID has at most 32)
function utf8Length(text) {
    let n = 0
    for (const ch of text || "") {
        const c = ch.codePointAt(0)
        n += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4
    }
    return n
}
