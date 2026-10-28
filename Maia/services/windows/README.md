# Maia window service

The list of windows of the session, for taskbars, docks and switchers. One process talks to the
compositor; every shell process gets the list and controls the windows through a Cap'n Proto
contract.

```text
 KWin ──org_kde_plasma_window_management──► maia-windows ──Cap'n Proto──► Maia.Windows (QML)
                                             (service/, Rust)              TasksModel in Lumen's
      ◄──────── set_state, close, ... ──────                ◄── control ── taskbar, Maia's dock
```

Rule: **data and control go through the service; streams and everything tied to frames bypass it**
(live window previews over PipeWire, the minimize animation target, drawing).

## Layout

| Path | What |
|---|---|
| `contract/windows.capnp` | The contract: `WindowService` (info, watch, control, icon), `WindowListener`, `WindowControl`. Read it first. |
| `service/` | `maia-windows` (Rust, tokio, one thread). |
| `service/src/kwin.rs` | KWin backend: the Wayland protocol → `BackendEvent`s, `Command`s → requests. |
| `service/src/backend.rs` | What a backend and the service exchange (channels; a second compositor = a second backend). |
| `service/src/model.rs` | The window store: order, changes, last activation (pure logic). |
| `service/src/apps.rs` | Which application a window belongs to (desktop entries), like Plasma's `TaskTools`. |
| `service/src/rpc.rs` | The Cap'n Proto server: snapshot, then changes, to every listener; control; icons. |
| `service/src/launch.rs` | Starting applications from `Exec=`. |
| `service/tests/service.rs` | The service over a real Cap'n Proto connection with a fake backend. |
| `qml/` | QML module `Maia.Windows` (static, linked into `appMaiaServer`). |
| `qml/ServiceConnection.*` | The connection of a process (KJ thread, never blocks the GUI, reconnects every second). |
| `qml/WindowSource.*` | The window list of the process; the models read it. |
| `qml/TasksModel.*`, `qml/AbstractTasksModel.h` | The model with the API and role names of Plasma's `org.kde.taskmanager`. |
| `qml/tests/tst_tasksmodel.cpp` | The model on a fake source, checked by `QAbstractItemModelTester`. |

## Using it from QML

```qml
import Maia.Windows as Windows

Windows.TasksModel {
    id: tasksModel
    groupMode: Windows.TasksModel.GroupApplications   // or GroupDisabled: one row per window
}

Repeater {
    model: tasksModel
    delegate: TaskButton {
        icon: model.decoration          // QIcon, e.g. for Kirigami.Icon
        text: model.display             // window title; application name for a group
        active: model.IsActive
        onClicked: tasksModel.requestActivate(tasksModel.makeModelIndex(index))
    }
}

// Roles by enum, as in Plasma
tasksModel.data(index, Windows.AbstractTasksModel.LastActivated)
```

QML written for `org.kde.taskmanager` mostly needs only the import changed. Not there (yet):
launchers / pinned applications (they belong to a future service), startup notifications,
activities, filtering by screen or virtual desktop, `requestPublishDelegateGeometry`.

## Running

The session scripts start the service (`Maia/DeployFiles/run_maia_wayland.sh.in`,
`run_maia_nested_wayland.sh`). By hand, inside a KWin session:

```bash
KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland ...   # KWin gives the protocol only to privileged clients
libexec/maia-windows                                   # socket: $XDG_RUNTIME_DIR/maia/windows-$WAYLAND_DISPLAY.sock
```

`MAIA_WINDOWS_SOCKET` overrides the socket path for both the service and the clients.

## Building and testing

Part of the normal CMake build (`cmake/MaiaRust.cmake` runs cargo). Separately:

```bash
cd Maia/services/windows/service && cargo test       # unit tests + the RPC test
ctest --test-dir <build> -R maia-windows             # cargo test and the model test
```

Dependencies: Rust 1.87+ (cargo) for building. Cap'n Proto comes from `3rdparty/capnproto`
(built with Maia and linked statically). For the Rust side only its schema compiler is needed:
a plain `cargo build` outside CMake takes `capnp` from PATH, or from `MAIA_CAPNP_EXECUTABLE`.

## Frequent changes (dragging, resizing)

KWin reports the geometry of a window on every frame while it is dragged or resized. Two things
keep that cheap for the clients:

- the service sends the changes of one window at most once per frame (`service/src/throttle.rs`,
  `CHANGE_INTERVAL` in `rpc.rs`), always with the latest state;
- `TasksModel` reports only the roles that changed (`changedRoles` in `qml/TasksModel.cpp`), so a
  geometry change re-evaluates only bindings on `Geometry`, and a task bar button does nothing.

To reproduce a drag without a mouse in a nested session, load a KWin script on the nested session
bus that moves the active window from a timer:

```js
const window = workspace.activeWindow;
let step = 0;
const timer = new QTimer();
timer.interval = 5;
timer.timeout.connect(function () {
    if (++step > 400) { timer.stop(); return; }
    const g = window.frameGeometry;
    window.frameGeometry = { x: 100 + (step % 300), y: g.y, width: g.width, height: g.height };
});
timer.start();
```

```bash
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript /path/to/drag.js drag
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
```
