.pragma library

// The frontend's own glyphs (assets/icons) for actions shown as icons (a notification's actionIcons):
// the keys of media players' buttons. Any other key comes from the icon theme, so that no glyph
// file that does not exist is ever asked for.
const names = [
    "media-playback-start",
    "media-playback-pause",
    "media-playback-stop",
    "media-skip-backward",
    "media-skip-forward",
]

// The glyph of an action key ("media-playback-pause" or "-symbolic"), "" none
function glyph(key) {
    const name = key.endsWith("-symbolic") ? key.slice(0, -"-symbolic".length) : key
    return names.indexOf(name) >= 0 ? name + "-symbolic" : ""
}
