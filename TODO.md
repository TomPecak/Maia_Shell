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
