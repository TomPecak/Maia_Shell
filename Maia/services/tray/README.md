# maia-tray-service

The system tray of a Maia session. Applications show their tray icons as they do on every Linux
desktop (StatusNotifierItem over D-Bus); the service keeps them, and every shell draws them its own
way: a shell that restarts, or is switched for another, finds the icons as they were.

The whole picture (what reaches it, its modules, its socket, who uses it, the API):
[docs/maia-tray-service.svg](docs/maia-tray-service.svg); how trays work on Linux:
`doc/diagrams/linux-system-tray.svg`.

```
applications ──D-Bus: RegisterStatusNotifierItem──► watcher ──┐
     │  ▲                                                     ├──► hub: the items ──Cap'n Proto──► shells
     │  └── Activate, Scroll, Event(clicked), token ◄─────────┤    batches, ≤ 1 per frame   TrayHost
     └──── org.kde.StatusNotifierItem, com.canonical.dbusmenu ─┘  (one task per item)     (Maia.Tray)
X11 icons ──XEmbed──► xembedsniproxy (KDE) ──► an item like any other
```

| Door | For | What |
|---|---|---|
| `org.kde.StatusNotifierWatcher` (session D-Bus) | every application: Qt (`QSystemTrayIcon`, `KStatusNotifierItem`), GTK through libayatana-appindicator, Electron and Chromium, `xembedsniproxy` | `RegisterStatusNotifierItem` (a bus name, an object path, or both), `RegisterStatusNotifierHost`, `RegisteredStatusNotifierItems`, `IsStatusNotifierHostRegistered` (always true: the service is a host), the four signals |
| `TrayHost` (Cap'n Proto, `tray-<display>.sock`) | shells (`Maia.Tray`) | the items (snapshot, then batches), activate and secondary activate with an activation token, scroll, the application's own context menu, `openMenu` → a `Menu` while the shell shows it |

| Directory | What it is |
|---|---|
| `contract/tray.capnp` | The contract, with its rules |
| `service/` | The service (Rust): `watcher.rs` the watcher (or a host of another one), `sni.rs` one task per item, `menu.rs` menus, `model.rs` and `markup.rs` an item's properties as plain values, `image.rs` icons as files, `desktop.rs` the item's application, `hub.rs` the shared state and the batches, `rpc.rs` the Cap'n Proto door |
| `qml/` | `Maia.Tray`, for shells: `Tray`, `TrayItemsModel`, `TrayMenu` |
| `tools/fake-tray-item.py` | An application with an item and a menu, driven from its standard input, for tests and by hand |

## The rules

- **The watcher and the only host.** The service owns `org.kde.StatusNotifierWatcher` and
  `org.kde.StatusNotifierHost-<pid>` from the start of the session, before the shell: Qt hides an
  icon while no host is registered. When another program keeps the watcher's name (Plasma's kded
  module), the service waits in the name's queue and is a host of that watcher meanwhile; Maia's
  `kded6rc` keeps kded's module off.
- **Nothing waits for an application.** Each item has its own task: it reads all properties
  (`GetAll`) after any signal of the item, at most every 100 ms (an animated icon is a few reads a
  second), with a time limit of 5 s per call. An item that never answers is never shown; one whose
  bus name goes is removed. A click is passed on without waiting for the answer.
- **Only data.** Titles and tool tips become plain text; how an item looks, and where it goes, is
  the shell's. `TrayItemsModel` gives the order (by category, then by age) and the rule that items
  that need attention are taken first when places are few; the filter and the number of places
  are the shell's.
- **Icons are names or files.** A theme name stays a name (the shell's theme draws it); a name found
  in the application's own icon directory (`IconThemePath`) becomes its file; pixels
  (`IconPixmap`, a menu entry's `icon-data`) are written as PNG of at most 64 px into
  `$XDG_RUNTIME_DIR/maia/tray-<display>/` (memory, private). A file is named by its content: an
  animation's frames and a menu opened again are written once, a new image is a new URL, and a
  file is removed 10 s after its last use.
- **Menus only while open.** `openMenu` reads the application's menu (`AboutToShow`, `GetLayout`)
  and sends the whole tree, again after every change (at most one a frame); the shell's `Menu`
  keeps it open, dropping it tells the application "closed". `TrayMenu` updates its levels by entry
  id, so a changed label changes one row. A picked entry gets the activation token first
  (`ProvideXdgActivationToken`), so "Show window" may raise it on Wayland.
- **Keys for later.** Each item has a `key` that stays across restarts of its application (its
  desktop entry and its Id), for hiding or pinning icons in Maia Settings.

## The shells

- **Maia** (`frontends/Maia/shell/tray/`): a plate of its own next to the clock's, in its style
  and of its width (a vertical dock strip) or height (a horizontal one), below it or to its left.
  At most four places; with more items, or passive ones, the last is "+N", which opens a panel
  with all of them. A tap activates, a long press or a right click opens the menu (Maia's menus,
  submenus over their menu), the middle button and the wheel go to the application. No items, no
  plate.
- **Lumen** (`frontends/Lumen/shell/windows/`): the icons in the taskbar left of quick settings,
  with their tool tips; "^" opens the passive ones; menus above the icon in Lumen's look, submenus
  to the side.

## Trying it

In a nested session (`run_maia_nested_wayland.sh`, its own D-Bus bus), or in the Maia session:

```bash
Maia/services/tray/tools/fake-tray-item.py --title Chat --status NeedsAttention
Maia/services/tray/tools/fake-tray-item.py --pixmap ff8800 --menu "Show,-,Pause,Quit"
```

It prints what the tray does to it (`Activate 0 0`, `Event 2 clicked`) and takes commands on its
standard input: `status Passive`, `title …`, `icon …`, `pixmap rrggbb`, `menu a,-,b`, `quit`.

## Tests

- `maia-tray-service-cargo-test`: the parts on their own, and the service on a private dbus-daemon
  with zbus applications that register by name and by path, a shell over Cap'n Proto: items,
  pixels as files, bursts of signals as one read, clicks with the token first, menus (layouts,
  changes, clicks, closed), items that go, another watcher.
- `maia-tray-qml`: `Maia.Tray` against the real service with `fake-tray-item.py`.
- `maia-frontend-components`, `lumen-components`: the plate, the overlay, Lumen's tray button.
