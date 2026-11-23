.pragma library

// Where a swiped row of the notification center goes when the finger lifts. Deleting cannot be
// undone, so only one thing does it: a deliberate drag past `commit`. A flick, however fast, at most
// opens the button; so a slip while scrolling costs nothing.

const closed = "closed"
const revealed = "revealed"
const clear = "clear"

// px/s: faster than this the direction of the movement decides, not the position
const flickSpeed = 400
// A flick shorter than this was not meant
const minimumFlick = 12

// offset: how far left the card is (px); velocity: of the finger, negative = to the left;
// reveal: where the card rests with the button open; commit: past this letting go deletes
function settle(offset, velocity, reveal, commit) {
    if (offset >= commit)
        return clear
    if (offset <= 0)
        return closed
    if (velocity < -flickSpeed && offset >= minimumFlick)
        return revealed
    if (velocity > flickSpeed)
        return closed
    return offset >= reveal / 2 ? revealed : closed
}
