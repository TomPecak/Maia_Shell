# Maia.CrossProcessState

Properties and signals shared by the processes of a session, declared in QML like `Settings {}`.
Made for shells split into processes (the Maia frontend runs each layer-shell layer as its own
process): one layer opens the notification center, the others know at once.

```qml
import Maia.CrossProcessState

// shell/ShellState.qml: the shared state of a frontend, declared once
CrossProcessState {
    category: "MaiaShell"                         // same category = same values
    property bool notificationCenterOpen: false
    property string dockEdge: "top"
    signal notificationTapped(int notificationId) // an event for the other processes
}

// In the longest-living process (the Maia frontend's Main.qml): it keeps the state
ShellState { host: true }

// In every layer
ShellState { id: shell }
NotificationPopupsModel { suppressed: shell.notificationCenterOpen }        // a binding
Connections { target: shell; function onNotificationCenterOpenChanged() { … } }
Button { onClicked: shell.notificationCenterOpen = true }                   // an assignment
```

## What a user gets

- **Ordinary QML properties**: bindings to them, `on…Changed`, `Behavior`s. A change in any process
  arrives in the others as if it had been assigned there.
- **Signals as events**: a declared signal emitted in one process is emitted in every other one,
  with its arguments (an event is a moment: a process that comes later does not get it).
- `synced`: the values are the session's (the host was reached, or this is the host). Before that
  an object has its declared values; e.g. `Behavior on x { enabled: shell.synced }` does not animate
  the jump at start.
- Values: what `QDataStream` writes: bool, numbers, strings, url, color, date, lists and maps of
  these; JavaScript objects and arrays travel as maps and lists.

## Rules (as for `Settings {}`)

1. Shared properties are values, not bindings: `property bool open: false`, never
   `property bool open: other.open` (a change from another process replaces the binding). Bind *to*
   them.
2. Objects and lists change as a whole: `shell.list = [...shell.list, item]`, never
   `shell.list.push(item)` (nobody hears an inner change, as with any `var`).
3. Declare a category's properties in one file with one set of defaults (two objects with different
   defaults end with the same value, but which one is not defined).
4. `category` and `host` are set once, in the declaration.

## How it works

```
 host process (host: true)                          participants
 ┌────────────────────────────┐   Unix socket   ┌──────────────────┐
 │ Link: QLocalServer          │◄───────────────│ Link: QLocalSocket│  LayerTop
 │ the values of every category│◄───────────────│ Link: QLocalSocket│  LayerOverlay
 └────────────────────────────┘                  └──────────────────┘
   $XDG_RUNTIME_DIR/maia/cross-process-state-$WAYLAND_DISPLAY.sock (+ .lock)
```

- **Reflection**: when an object is complete, `QMetaObject` gives the properties and signals its
  QML declaration added; each notify signal and each declared signal is caught with its arguments
  (as `QSignalSpy` does). A value from elsewhere is written with `QMetaProperty::write`, an event
  emitted with `QMetaMethod::invoke`; neither is sent back.
- **One link per process** (`Link`), shared by its objects; objects of a category in one process see
  each other at once, without the socket.
- **Never blocking**: sockets are asynchronous, nothing waits for bytes. Changes made in one turn of
  the event loop leave as one write; a burst of changes of one key leaves as its last value (10000
  assignments in a JavaScript loop: one message).
- **Never polling**: a participant without a host watches the socket's directory (inotify through
  `QFileSystemWatcher`) and connects when a new host's socket appears.
- **The host** holds a `QLockFile` next to the socket: a second `host: true` takes part instead (a
  warning) and takes over when the first one is gone; the lock of a crashed host is stale (its pid
  is gone), so a new host takes over its socket at once.
- **A host that comes (back)**: participants join with their values; a changed value wins over the
  host's declared default, so a restarted host gets the session's state back. Between two changed
  values the host wins.
- **Writes at once**: a participant's change goes to the host and comes back to everyone, the writer
  included, in the host's order; until its own change is back, a participant ignores other values
  of that key. Two processes writing at once end with one value everywhere, and none flickers
  through the other's value.
- The protocol (`Protocol.h`) is private to the library and versioned.

`$MAIA_CROSS_PROCESS_STATE_SOCKET` names another socket (tests).

## Tests

`tst_crossprocessstate` (CTest `maia-crossprocessstate`) starts real processes
(`crossprocessstate-peer`, `tests/peer.cpp`: a CrossProcessState in QML, driven through its
standard input):

- every value type in every process; a late participant gets the current state;
- a participant before its host keeps its change and connects when the host appears (inotify);
- a restarted host gets the state back; a crashed host (SIGKILL, socket and lock left) is replaced;
- a second host takes part instead, and takes over when the host crashes; two hosts started at the
  same moment are one host (5 rounds);
- a killed participant does not disturb the others and comes back with the state;
- changes made while there is no host reach the next one; a host restarted 5 times (clean and
  crashed) ends in one state;
- a broken process (a 2 GiB frame, a frame that is no message, another protocol version) is
  disconnected, the host goes on;
- a participant waiting for a host uses no processor time (measured from /proc: 0 ms in 2 s);
- 10 participants see each event once;
- 50 writes at once from two processes end the same everywhere;
- events reach every other process once, also with a JavaScript object as the argument;
- 10000 assignments in one turn are one message;
- a change reaches another participant in about 1–5 ms (measured, 20 changes);
- in one process: objects share without a host, declarations found by reflection.
