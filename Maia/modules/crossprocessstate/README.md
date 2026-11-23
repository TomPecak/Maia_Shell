# Maia.CrossProcessState

Properties and signals shared by the processes of a session. Made for shells split into processes
(the Maia frontend runs each layer-shell layer as its own process): one layer opens the
notification center, the others know at once.

## Use

**1. Declare the state once**, as a singleton of your frontend:

```qml
// shell/ShellState.qml
pragma Singleton
import Maia.CrossProcessState

CrossProcessState {
    category: "MaiaShell"                         // same category = same values

    property bool notificationCenterOpen: false
    property bool controlCenterOpen: false
    // Derived in each process from what is shared
    readonly property bool anyOpen: notificationCenterOpen || controlCenterOpen

    signal notificationTapped(int notificationId) // an event for the other processes
}
```

```
# qmldir of the frontend
singleton ShellState 1.0 shell/ShellState.qml
```

**2. Use it by name, in any file of any process:**

```qml
import MaiaFrontend

Sheet { open: ShellState.notificationCenterOpen }                  // a binding
Button { onClicked: ShellState.notificationCenterOpen = true }     // an assignment

Connections {
    target: ShellState
    function onNotificationTapped(id) { list.scrollTo(id) }        // an event from another process
}
```

That is all. There is no server to start and no process to name: the first process hosts the state,
and when it is gone another one takes over with the state. `CrossProcessState` can also be
instantiated like any type (several objects of one category share their values); the singleton is
simply the most comfortable way, with one declaration and one set of defaults.

## What you get

- **Ordinary QML properties**: bindings to them, `on…Changed`, `Behavior`s. A change in any process
  arrives in the others as if it had been assigned there.
- **Signals as events**: a declared signal emitted in one process is emitted in every other one,
  with its arguments (an event is a moment: a process that comes later does not get it).
- **`readonly` properties are derived, not shared**: each process computes them from the shared ones.
- `synced`: the values are the session's. False only for a moment: at the start of a process that is
  not the first, and while another process takes over. `Behavior on x { enabled: ShellState.synced }`
  does not animate the jump at start.
- Values: bool, numbers, strings, url, color, date, lists and maps of these; JavaScript objects and
  arrays travel as maps and lists.

## Two rules

1. A shared property holds a value, not a binding: `property bool open: false`, never
   `property bool open: other.open` (a change from another process replaces the binding). For a
   value computed from others use `readonly property`.
2. Objects and lists change as a whole: `ShellState.list = [...ShellState.list, item]`, never
   `ShellState.list.push(item)` (nobody hears an inner change, as with any `var`).

## How it works

```
 the process that hosts                             the others
 ┌────────────────────────────┐   Unix socket   ┌───────────────────┐
 │ Link: QLocalServer          │◄───────────────│ Link: QLocalSocket │  LayerTop
 │ the values of every category│◄───────────────│ Link: QLocalSocket │  LayerOverlay
 └────────────────────────────┘                  └───────────────────┘
   $XDG_RUNTIME_DIR/maia/cross-process-state-$WAYLAND_DISPLAY.sock (+ .lock)
```

- **Reflection**: when an object is complete, `QMetaObject` gives the properties and signals its
  QML declaration added; each notify signal and each declared signal is caught with its arguments
  (as `QSignalSpy` does). A value from elsewhere is written with `QMetaProperty::write`, an event
  emitted with `QMetaMethod::invoke`; neither is sent back.
- **One link per process** (`Link`), shared by its objects. Objects of a category in one process see
  each other at once, without the socket; a category is joined once per connection.
- **The election is the kernel's**: the host holds `flock()` on the lock file, released when its
  process ends, however it ends. Whoever did not get it watches the holder's exit through a
  `pidfd` and tries again then (the end of the connection is not enough: a dying process may close
  its sockets before its lock).
- **Never blocking**: sockets are asynchronous, nothing waits for bytes. Changes made in one turn of
  the event loop leave as one write; a burst of changes of one key leaves as its last value (10000
  assignments in a JavaScript loop: one message).
- **Never polling**: a waiting process sleeps on the `pidfd` and on inotify (the host's socket
  appearing).
- **A new host collects the state**: every value has a revision, and the newest of each key wins, so
  a change made while the host was going away is not lost. Between equal revisions the host wins.
- **Writes at once**: a participant's change goes to the host and comes back to everyone, the writer
  included, in the host's order; until its own change is back, a participant ignores other values
  of that key. Two processes writing at once end with one value everywhere, and none flickers
  through the other's value.
- The protocol (`Protocol.h`) is private to the library and versioned.

`$MAIA_CROSS_PROCESS_STATE_SOCKET` names another socket (tests). Linux 5.3 or newer (`pidfd`).

## Tests

`tst_crossprocessstate` (CTest `maia-crossprocessstate`) starts real processes
(`crossprocessstate-peer`, `tests/peer.cpp`, driven through its standard input):

- a singleton used by name in several processes, with a derived property, an event and a host that
  crashes; every value type in every process; a single process alone; a late process;
- a host that ends or crashes is replaced with the state; files left by a crashed host;
- 6 processes started at once elect one host (5 rounds); hosts dying one after another, clean and
  crashed, leave one state;
- a change made as the host dies is not lost (5 rounds); a change right before a process ends arrives;
- a killed participant does not disturb the others; a broken process (a 2 GiB frame, a frame that is
  no message, another protocol version) is disconnected, the host goes on;
- 50 writes at once from two processes end the same everywhere; events reach every other process
  once, also with a JavaScript object; 10 participants;
- 10000 assignments in one turn are one message; a change arrives in about 1–5 ms; an idle process
  uses no processor time (from /proc: 0 ms in 2 s);
- several objects in one process: fifty join once and all get a change; a `Loader` made again gets
  the current value; the host goes on without its object.
