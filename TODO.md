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

Area: `Maia/BackendLib/server/SessionService.cpp`, `Server::sessionLogout` (`server/Server.cpp`),
the session script `Maia/DeployFiles/run_maia_wayland.sh.in`.

### What happens

Log out: `SessionService::logout` → `Server::sessionLogout` → `QCoreApplication::exit(0)`. Maia
exits, the session script ends, and KWin (`--exit-with-session`) quits and takes every window with
it. Restart and shut down call logind (`Reboot` / `PowerOff`) at once, and systemd then kills the
session. No application is asked to close first. Unsaved documents are lost, and browsers report
that they "did not shut down correctly".

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
- Keep the guard of nested development sessions: there `SessionService` only logs suspend,
  restart and shut down (`MAIA_NESTED_SESSION=1`, set by `run_maia_nested_wayland.sh`).

### Done when

In a nested session whose system bus is a stand-in, so nothing reaches the real logind
(`DBUS_SYSTEM_BUS_ADDRESS` pointing at a private `dbus-daemon`; `dbus-monitor` on it records the
`login1` calls): an editor with unsaved text asks to save before logout; logout with only closed-on-request windows
ends within a second or two; a window that does not close shows the dialog after the timeout.

---

## 3. Notifications: no notification server in the Maia session

Area: a new service, e.g. `Maia/services/notifications/` (same layout as `Maia/services/windows`).

### What happens

Applications send notifications to `org.freedesktop.Notifications` (D-Bus, freedesktop
Desktop Notifications specification). In Plasma, plasmashell owns that name. Maia replaces
plasmashell, so nobody owns it: in the Maia session (checked 2026-10-28) the name has no owner, and
D-Bus activation starts `plasma_waitforname`, which only waits for plasmashell. Notifications of
all applications are lost.

### Fix

- A notification service (Rust, like `maia-windows`): owns `org.freedesktop.Notifications` on the
  session bus (`Notify`, `CloseNotification`, `GetCapabilities`, `GetServerInformation`, signals
  `NotificationClosed`, `ActionInvoked`), keeps the list and history, and serves it to the
  frontends over a Cap'n Proto contract (snapshot + changes, actions back).
- A QML module for the frontends (like `Maia.Windows`); each frontend shows the popups and the
  notification centre in its own style.
- Start it from the session scripts, before Maia.

### Done when

`notify-send "Test" "Body"` and a notification with actions (e.g. from a browser) show up in
Lumen and the Maia frontend, and the action reaches the application; tests for the D-Bus side and
the contract, as for the window service.

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

## 6. Settings: the configuration files have the version in their name

Area: `Maia/MaiaServerApp/main.cpp` (`setApplicationName`, about line 92),
`Maia/BackendLib/server/FrontendManagerService.cpp` (`readActiveFronted`, `saveActiveFronted`),
`Maia/BackendLib/server/LocaleSettingsService.cpp` (`loadSettings`, `saveSettings`).

### What happens

Maia keeps its settings in two files in `~/.config/Maia/`, and both names contain the Maia version:
- `Maia_<version>.conf`: everything QML stores with `Settings` from `QtCore` (Lumen's theme and
  accent, Lumen's timer, the dock edge of the Maia frontend, XPLuna's notes and warnings), and the
  favourite applications (`QSettings` in `server/FavoriteAppsListModel.hpp`). QSettings derives the
  name from the application name, which `main.cpp` sets to `Maia_<version>`.
- `maiarc_<version>`: what the C++ services store with KConfig (the active frontend, the 24-hour
  clock).

After an update to a new version, Maia reads new, empty files: every user setting falls back to
its default, although the old files are still there (`Maia_0.1.0.conf` and `Maia_0.2.0.conf` exist
side by side on a developer machine). The two mechanisms also write two different files for no
reason. The Cutefish code (`BackendLib/cutefish/dock/docksettings.cpp`) writes yet another file
under a foreign name (`cutefishos/dock`).

### Fix

- Fixed file names without the version, e.g. `~/.config/Maia/maia.conf` for QML and the services
  (one file, or one per owner, but never per version). The application name used for the
  configuration must not change with the version. If the version must stay in the application
  name for other reasons, give the QML `Settings` an explicit `location` instead.
- If the format ever changes incompatibly, a schema version as a key inside the file, with a
  migration step, not a new file.
- Migration of what exists: when the new file is missing, copy the values of the newest versioned
  file once (`Maia_<x.y.z>.conf`, `maiarc_<x.y.z>`, highest version first), then leave the old files
  alone.
- Until item 7 replaces it, keep one convention for new code: the frontends use QML `Settings` with
  their own `category` (e.g. `LumenFrontend`, `MaiaDock`), no new files.

### Done when

In a nested session with isolated XDG directories: settings made with version A survive a start
with version B (change `MAIA_VERSION` in a test build), no new versioned file appears, and the
values of an old `Maia_0.2.0.conf` / `maiarc_0.2.0` are taken over on the first start.

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
