# TODO

Known problems and planned work that is not done yet. Written for whoever picks it up next,
human or AI agent: each item says what is wrong, why, where the code is, what the fix should look
like and how to know it is done. Remove an item when it is fixed (the history stays in git).

Before working on an item, read the README of the area (e.g. `Maia/services/windows/README.md`).
Test in a nested KWin session, never in the user's own session (see `README.md`, "Contribution").

---

## 1. Window service: application identification is simpler than Plasma's

Area: `Maia/services/windows/service/src/apps.rs` (`AppIndex::identify`).

### What it is for

Every window must be mapped to its desktop entry (`.desktop` file). That gives the application
name, icon, launcher URL, grouping by application and "start a new instance". A wrong or missing
match means a generic icon, the window title instead of the application name, wrong grouping in
the dock, or no "new instance".

### What Maia does now

Lookup order, first match wins (`AppIndex::lookup`):
1. `app_id` as a desktop entry id (case-insensitive, without `.desktop`);
2. `app_id` as `StartupWMClass`;
3. the X11 resource name as `StartupWMClass`;
4. the resource name as a desktop entry id;
5. reverse DNS: `app_id` `foo` → the first entry whose id ends in `.foo` (e.g. `org.kde.foo`);
6. the program of the process (`/proc/<pid>/exe` file name) against the program of `Exec=`.

It reads the `applications` directories of `$XDG_DATA_HOME` and `$XDG_DATA_DIRS` itself (no ksycoca).
After a miss it rescans at most every 5 s. This is enough for ordinary KDE/GNOME/Qt/GTK
applications. It was checked with Konsole, Dolphin and xeyes (no desktop entry: generic name,
icon from the compositor).

### What Plasma does that Maia does not

Reference: `plasma-workspace/libtaskmanager/tasktools.cpp`, `windowUrlFromMetadata`,
`servicesFromPid`, `servicesFromCmdLine` (Plasma 6.6).

- **Order:** Plasma tries `StartupWMClass` (resource name, then `app_id`) **before** the desktop
  entry id: an explicit `StartupWMClass` is a deliberate statement by the application. Maia tries
  the id first.
- **`app_id` that is a path:** an absolute path to a `.desktop` file, with or without the
  extension, is used directly.
- **`Name=` match:** `app_id` against the (untranslated) application name. A weak heuristic; skip
  `NoDisplay` entries.
- **Snap:** the process environment variable `BAMF_DESKTOP_FILE_HINT` (`/proc/<pid>/environ`) holds
  the path of the right desktop file.
- **AppImage:** the environment variable `APPDIR` points at the mounted image; its `*.desktop` file
  is the entry.
- **Command line instead of the binary:** Plasma matches `/proc/<pid>/cmdline` against `Exec=`:
  the full command, without the path, without arguments. It skips interpreters (`perl`) and looks at
  the script instead. Maia uses `/proc/<pid>/exe`, which for scripts and Electron apps is the
  interpreter (`python3`, `electron`) and may even match a wrong entry. This false positive is
  worse than no match.
- **Reverse DNS must be unique:** Plasma accepts the `*.app_id` match only when exactly one entry
  fits; Maia takes the first one.
- **Several entries for one key:** Plasma prefers the entry whose menu id starts with the key. This
  is the Steam case: the native `steam.desktop` and the Wine copy `wine-Programs-Steam-Steam.desktop`.

Other cases to check, which Plasma covers only through the generic rules above:
- Flatpak (desktop entries in `/var/lib/flatpak/exports/share/applications` and
  `~/.local/share/flatpak/exports/share/applications`: is that in the session's `XDG_DATA_DIRS`?);
- Chrome/Chromium web apps (`crx_<id>`, entries with `StartupWMClass`);
- Steam games (`steam_app_<id>`);
- Wine programs (`*.exe` classes);
- LibreOffice (one process, window classes per component: `libreoffice-writer`, ...);
- Java applications.

A possible further step beyond Plasma: on systemd distributions, applications started by KDE/GNOME
launchers run in a scope `app-<desktop id>@<n>.service` or `app-<launcher>-<desktop id>-<n>.scope`.
`/proc/<pid>/cgroup` then names the desktop entry exactly. This is the most reliable source when
present; check how Maia itself starts applications (`launch.rs` uses a plain process group, no
scope).

### Fix

- Bring `AppIndex::lookup` in line with the Plasma order and add the missing rules (path `app_id`,
  `Name=`, Snap, AppImage, command line with interpreter skipping, unique reverse DNS, preference on
  duplicates). Keep each rule a small, separately tested function. `apps.rs` already has
  temporary-directory tests to extend.
- Replace `/proc/<pid>/exe` matching with command line matching, or at least drop matches on known
  interpreters and runtimes (`python*`, `perl`, `sh`, `bash`, `electron`, `java`, `mono`, `wine*`).
- Consider the cgroup scope as the first rule (and start applications in scopes in `launch.rs`, as
  Plasma's `KIO::ApplicationLauncherJob` does).
- Keep identification cheap: it runs only for new windows or a changed `app_id`/resource name/pid
  (`WindowStore::upsert`). Rescans stay rate-limited.

### Done when

- Unit tests in `apps.rs` cover each rule, with desktop files in temporary directories and fake
  `/proc` data (make the `/proc` reads injectable, e.g. a small trait or a root path parameter).
- Manual check in a nested session with a Flatpak app, a Snap, an AppImage, a Python/Electron app
  and a Wine program, if available: correct name, icon and grouping, or no match (never a wrong
  one).

---

## 2. Session: close applications gracefully before the session ends

Area: `Maia/services/session/` (maia-session-service: `service/src/session.rs`, "Ending" in its
README), the window service `Maia/services/windows/`, the shells' log out / power menus.

### What happens

Log out: the session service answers at once and then stops the shell, its other children, KDE's
units and the compositor, which takes every window with it. Restart and power off ask logind first
and then end the session the same way. No application is asked to close first: unsaved documents
are lost, and browsers report that they "did not shut down correctly".

Plasma does it in steps (ksmserver, `org.kde.Shutdown`): ask every application to close, wait for
them (an application may refuse, e.g. "save changes?"), and only then end the session or call logind.

### Fix

- One shutdown sequence in the session service, the same for logout, restart and shut down:
  1. close every window: `WindowControl.close` of the window service
     (`Maia/services/windows`), which sends the compositor's close request, like the window's
     close button;
  2. wait until no windows are left (`WindowListener.removed`), with a timeout (Plasma: about 15 s);
  3. if windows remain, show which applications block (the frontend shows a dialog: "cancel" /
     "end anyway");
  4. then end the session (exit) or call logind.
- Respect logind inhibitors of type `shutdown` in block mode (`ListInhibitors`), and tell the user
  who blocks.
- Keep the guard of nested development sessions: there suspend, restart and power off must never
  reach the real logind (a stand-in system bus, as below).

### Done when

In a nested session whose system bus is a stand-in, so nothing reaches the real logind
(`DBUS_SYSTEM_BUS_ADDRESS` pointing at a private `dbus-daemon`; `dbus-monitor` on it records the
`login1` calls): an editor with unsaved text asks to save before logout; logout with only
closed-on-request windows ends within a second or two; a window that does not close shows the dialog after the timeout.

---

## 3. Notifications: done

Done 2026-11-13..15: `Maia/services/notifications/` (maia-notifications-service, `Maia.Notifications`,
`Maia.Notifications.Center`, `Maia.Notifications.Settings`). What is left is in `ROADMAP.md`. The
number stays so that references to items 4 to 7 keep their meaning.

---

## 4. System tray: no StatusNotifierItem host in the Maia session

Area: a new service or part of the notification service; the frontends' panels.

### What happens

Applications put their tray icons on the StatusNotifierItem protocol (D-Bus): they register with
`org.kde.StatusNotifierWatcher`, and the panel (the host) shows them. In Plasma, plasmashell is the
watcher and the host. In the Maia session the name has no owner (checked 2026-10-28): tray icons
(Discord, Steam, Nextcloud, network applets) do not appear, and some applications fall back to a
normal window or quit to the background without a way back. Old X11 tray icons (XEmbed) need a
bridge as well (`xembedsniproxy` from Plasma).

### Fix

- A service that owns `org.kde.StatusNotifierWatcher`, tracks the registered items and their
  properties (icon name or pixmap, tooltip, status, menu via `com.canonical.dbusmenu`), and serves
  them to the frontends over Cap'n Proto; activation, scrolling and menu actions go back through it.
- A QML model of the tray items for the frontends.
- Start `xembedsniproxy` in the session script for XEmbed icons.

### Done when

Icons of an application with an SNI tray icon and of an XEmbed one appear in Lumen's tray, react to
clicks, show their menus, and disappear when the application quits.

---

## 5. Rust: no `unsafe` in Maia's code

Area: `Maia/services/windows/service/src/kwin.rs` (the only `unsafe` today, about line 78).

### What it is

The KWin backend lets tokio poll the Wayland socket of the compositor connection:

```rust
let socket = unsafe { AsyncFd::register_with_interest(PollFd(raw_fd), Interest::READABLE)? };
```

`PollFd` holds the raw descriptor owned by the `wayland_client::Connection`. tokio made its safe
constructors (`AsyncFd::new`, `with_interest`) deprecated as unsound without I/O safety, and the
`unsafe` variant needs the caller to promise that the descriptor stays open as long as the `AsyncFd`
exists. Today that promise holds (both live in the same function, the `AsyncFd` is dropped first),
but only by the order of declarations, which a later change can break silently.

### Fix

Remove the `unsafe` and get the guarantee from the types instead. Options, best first:
- give tokio a descriptor it owns: `connection.backend().poll_fd().try_clone_to_owned()` (a `dup`
  of the socket; readiness is the same, as both refer to one open socket) wrapped in a type that
  tokio accepts through a safe constructor, if tokio 1.54 offers one for owned descriptors;
- or borrow it with a lifetime: an `AsyncFd` over a `BorrowedFd<'_>` of the connection, so the
  compiler rejects dropping the connection first;
- or let a crate do it that already wraps this safely (e.g. `calloop`, whose Wayland source is the
  usual way to drive `wayland-client`; that changes the event loop, so weigh it).

Then add `#![forbid(unsafe_code)]` to `service/src/lib.rs` and `main.rs` (and to every future Maia
crate), so new `unsafe` cannot come in unnoticed. Code that truly needs it (FFI) goes into its own
small module with `#[allow(unsafe_code)]` and a `// SAFETY:` comment for each block.

### Done when

`grep -rn unsafe` finds nothing in Maia's Rust sources (outside such a module), the crates build
with `forbid(unsafe_code)`, `cargo test` passes and the task bar still updates in a nested session.

---

## 6. Settings: a new Maia version starts with default settings

Area: `Maia/Paths/MaiaPaths.cpp` (`configDir`), the Rust services' copies of the same rule
(`Maia/services/appearance/service/src/paths.rs`, `Maia/services/notifications/service/src/settings.rs`),
the session scripts.

### What happens

Every Maia version keeps its settings in its own directory, `~/.config/maia/<version>/` (`maia.conf`
for QSettings and QML `Settings`, and a file named after each process that owns one:
`appMaiaServerrc` for KConfig, `maia-appearance-service.json`, `maia-notifications-service.json`,
`wayfire.ini`). This is by design: versions are installed side by side (`/opt/Maia/Maia_<version>`)
and must never share or overwrite each other's settings. The cost: after an update the user finds
every setting at its default (frontend, theme, favourites, do not disturb, applications turned off).
Older versions used `~/.config/Maia/Maia_<version>.conf` and `maiarc_<version>`.

### Fix

- On the first start of a version (its directory does not exist yet), offer to take over the
  settings of the newest older version: copy its directory (or the old `Maia_<x.y.z>.conf` /
  `maiarc_<x.y.z>` files), then leave the old ones alone. Ask once (a question in the shell or
  Maia Settings), or do it by default with an option to start clean.
- One place decides it (the session service, before the shell and the services start), so that
  every service reads the copied files.
- If a file format ever changes incompatibly: a schema version inside the file and a migration
  step, not a new file name.

### Done when

In a nested session with an isolated `XDG_CONFIG_HOME`: settings made with version A are there on
the first start of version B (a test build with another `MAIA_VERSION`), and a version started
again keeps its own settings without copying anything.

---

## 7. Settings: a settings service with a contract (under consideration)

Area: a new service, e.g. `Maia/services/settings/` (same layout as `Maia/services/windows`).

### Why

Settings are stored today by whoever needs them: QML `Settings` inside each frontend, KConfig
inside C++ services (item 6). That works for one value in one process, but:
- no change notification between processes: each layer of a frontend is its own process with its
  own QSettings cache, and a future Settings application could not change a value while the shell
  runs;
- no types, defaults or validation in one place, no migrations;
- no permissions: every frontend can read and overwrite everything, which collides with the
  sandboxed and AI-generated frontends of the roadmap (stage 7).

### Architecture (proposal)

The headless backend must not know what the settings of a frontend mean. Three kinds of settings,
three owners:
1. **Storage** (the settings service): a generic, typed key-value store in namespaces, with
   snapshot + `Watch` + `set` over Cap'n Proto, atomic writes and per-namespace permissions
   (capabilities: a frontend gets its own namespace only). It does not interpret values, like dconf
   does not know the meaning of GSettings keys.
2. **Environment settings with behaviour** stay with the service that acts on them and uses the
   store internally: the active frontend (session), the 24-hour clock (locale), and later
   appearance shared by all frontends and applications (dark mode, accent colour, fonts, icon
   theme: these also have to reach Qt/GTK applications, e.g. through the `org.freedesktop.appearance`
   settings of the desktop portal and the KDE colour scheme). These work headless and are the same
   in every frontend.
3. **Frontend state** (the dock edge, Lumen's accent choice, a collapsed widget): in the frontend's
   own namespace (`frontend.<id>.*`). The frontend owns the schema and the defaults, e.g. declared
   in its manifest, so a Settings application could show them without code; the service only
   stores the values.

On the QML side a module like `Maia.Windows`: an object with properties per key and a write method,
so a frontend swaps its storage in one place (the Maia frontend's `shell/dock/DockState.qml` is
written as that one place).

### Open questions

- One service or part of the shell service of stage 2 (one process, separate contract).
- File format (TOML or JSON, one file per namespace?), and whether KConfig files of KDE
  (`kdeglobals`, `kwinrc`) are ever written through it or only by their own tools.
- Multiple screens: keys per output (the dock edge per screen), keyed by a stable output name.

### Done when

Decided whether to build it; if yes: the active frontend, the 24-hour clock, Lumen's settings and the
dock edge go through the service, a change made by one process reaches the others at once, and a
frontend cannot write outside its namespace (tests for the contract and the permissions, as for the
window service).

---

## 8. Appearance: light/dark and the accent colour belong to the appearance service

Area: `Maia/frontends/Lumen/theme/Theme.qml` (`Settings { category: "LumenFrontend" }`: `dark`,
`accentIndex`), `Maia/frontends/Maia/theme/Theme.qml` (`Settings { category: "MaiaAppearance" }`:
`dark`), Maia Settings (it imports Lumen's theme), `Maia/services/appearance/` (today window
decorations only).

### What happens

Light/dark and the accent are kept by each frontend in the shared `maia.conf` (QSettings):
- each frontend keeps its own dark mode (`[LumenFrontend] dark`, `[MaiaAppearance] dark`). That
  each has its own is right (decided 2026-11-26, below); that the frontends keep it themselves, in
  one shared file, is not: nobody outside a frontend knows its choice;
- Maia Settings looks like Lumen by reading Lumen's private keys (`LumenFrontend/accentIndex`),
  a detail of one frontend;
- QSettings caches per process: a change in the shell reaches Maia Settings and other processes
  only at their next start (the layers of the Maia frontend tell each other, through `ShellState`);
- ordinary applications never learn it: Firefox, GTK and libadwaita apps ask the desktop portal
  (`org.freedesktop.appearance`: `color-scheme`, `accent-color`), Qt/KDE apps read `kdeglobals`.

### Fix

- `maia-appearance-service` owns the choice and keeps it in `maia-appearance-service.json`:
  - the colour scheme: light, dark (later: by the time of day), **remembered for each frontend on
    its own** (decided with the user, 2026-11-26): Lumen can be light while Maia is dark, and each
    comes back as it was left. The same way the service already remembers the window decoration of
    every frontend (`activateFrontend`, `FrontendLook`); a frontend seen for the first time gets
    the default it declares;
  - the scheme in force is that of the active frontend: when the frontend is switched, the service
    applies the new one's scheme, and so do the other applications (below);
  - the accent: per frontend like the scheme, or one for all (still to decide), as a **name** from a shared set (as GNOME does: blue, teal, green, yellow, orange,
    red, pink, purple, slate), not a colour value: the name is data, each frontend maps it to its
    own tones for light and dark (Lumen's palettes keep their contrast rules); the portal gets an
    RGB value of the service's reference tones.
- Contract: the state and its changes (watch), `setColorScheme`, `setAccent` for the active
  frontend (a frontend changes only its own; Maia Settings changes the active one's);
  `Maia.Appearance` gives `colorScheme` and `accent` to QML, live in every process (the shells, all
  layers of the Maia frontend, Maia Settings, Maia's apps). Then the Maia frontend's layers need no
  signal of their own for it (`ShellState.darkModeSet` goes).
- The frontends' `Theme.qml` read `Maia.Appearance` instead of their own `Settings`; the shells'
  tiles and Maia Settings' Appearance page write through it.
- To the other applications: the portal's `org.freedesktop.appearance` (through the KDE portal
  backend, which reads `kdeglobals`, or a small backend of Maia's own) and `kdeglobals`
  (`ColorScheme`, accent) for Qt/KDE apps, written by the service only.
- Then `maia.conf` keeps no shared look. What else is in it moves as the roadmap says (favourite
  apps: their contract; Lumen's timer: the timer service; the dock edge: frontend state, item 7),
  and `maia.conf` can go.

### Done when

Switching dark mode in a frontend changes at once: that frontend (all layers of the Maia frontend),
an open Maia Settings window, and a GTK app (e.g. a GNOME app) and a Qt app that follow the system
scheme. Lumen set light and Maia set dark: switching between them switches the look each time, and
after a new session each frontend starts as it was left. Tests for the contract and for the stored file, as for the
decorations.

