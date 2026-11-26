# Maia Shell roadmap

What is done and what comes next, **ordered by how much it matters to the people who use Maia
every day**: first what loses work or breaks daily use, last what only developers notice. Within a
group, the first item is the next one to do.

`TODO.md` describes single problems in depth (what is wrong, where the code is, how to fix it,
when it is done); items here link to it as "TODO n". Tick an item off here when it is done, and
remove its TODO entry.

Last reviewed: 2026-11-15.

---

## Where Maia stands

Maia runs as an everyday Wayland session (KWin, or Wayfire) with **Lumen** as the reference shell.
System logic lives in Rust services, shells are QML views on them, connected by Cap'n Proto
contracts (see "Principles" below).

| Area | State |
|---|---|
| Session | `maia-session-service` starts the compositor, KDE's helpers (polkit agent, KWallet, PowerDevil, kaccess) and Maia's services from `session.toml`; log out, restart, power off through logind; sessions "Maia (KWin)" and "Maia (Wayfire)" |
| Windows | `maia-windows-service` + `Maia.Windows`: the task bar shows the real windows (KWin, and Wayfire through a plugin), activate, minimize, close, fullscreen state |
| Network | `maia-network-service` + `Maia.Network`: Wi-Fi in Lumen's quick settings and the Wi-Fi page of Maia Settings (passwords, hidden networks, hotspot, sharing by QR code, details) |
| Power | `maia-power-service` + `Maia.Power`: batteries (also of a mouse or headphones), brightness, keyboard backlight, power modes, battery warnings; Power page in Maia Settings |
| Notifications | `maia-notifications-service` + `Maia.Notifications`, `.Center`, `.Settings`: popups, the notification center, do not disturb, sounds, quiet over fullscreen apps, progress of copies in Dolphin and of Maia's apps; Notifications page in Maia Settings |
| Appearance | `maia-appearance-service` + `Maia.Appearance`: window decorations per frontend |
| Maia Settings | Wi-Fi, Power, Notifications (English only for now) |
| Shells | Lumen (desktop, the reference), Maia (tablet face), older: Ubuntu 24.04, XPLuna, Experimental |

---

## 1. Work is lost or the session is unsafe

- [ ] **Close applications before logout, restart and power off** (TODO 2). Today the session ends
      at once: unsaved documents are lost, browsers report a crash. Ask every window to close, wait,
      show who blocks ("cancel" / "end anyway"), respect logind's shutdown inhibitors.
- [ ] **Lock screen.** There is none: a laptop left alone stays open. Decide between KDE's
      `kscreenlocker` (test only in a virtual machine) and a lock screen of Maia's own (the session
      service locks through logind's `Lock` signal; the shell draws it; unlocking through PAM in a
      small helper). The notification setting for the lock screen is ready
      (`NotificationCenter.lockScreenNotifications`). Also: lock before suspend, lock on lid close.

## 2. Everyday things that do not work yet

- [ ] **System tray** (TODO 4). Tray icons of Discord, Steam, Nextcloud and others do not appear;
      some apps cannot be brought back once hidden. StatusNotifierWatcher/Host with menus
      (DBusMenu), XEmbed icons through `xembedsniproxy`.
- [ ] **Autostart of the user's applications** (`~/.config/autostart`, `/etc/xdg/autostart`):
      nothing starts them today (Nextcloud, chat apps). The session service starts them after the
      shell, honouring `Hidden`, `OnlyShowIn`/`NotShowIn`, `X-GNOME-Autostart-enabled`, and skipping
      what systemd units already start.
- [ ] **Sound.** Lumen has volume and mute through PulseAudioQt inside the shell. Missing: an
      on-screen display for the volume keys (and check that the keys work at all: in Plasma,
      plasmashell handles them), choosing the output and input device, and a sound service
      (`maia-audio-service` on PipeWire) so every shell and Maia Settings share it. A Sound page in
      Maia Settings.
- [ ] **Removable drives.** Plug in a USB stick: nothing tells you, nothing mounts it. Mount
      (UDisks2), a notification with "Open" and "Eject", safe removal from the shell.
- [ ] **Bluetooth.** The quick settings tile is a mock-up. On/off, paired devices, connect and
      disconnect (BlueZ), pairing with a code; a Bluetooth page in Maia Settings. Device batteries
      already come from `maia-power-service`.
- [ ] **Portals.** Check that `xdg-desktop-portal` with the KDE backend works in the Maia session:
      file chooser of Flatpak apps, screen sharing in browsers and video calls, screenshots. Fix
      what does not.
- [ ] **Media controls (MPRIS).** Play/pause/next of the playing app in the quick settings or a
      widget, and the media keys.

## 3. Things that work but are wrong or incomplete

- [ ] **Correct application of a window** (TODO 1). Wrong or generic icons and grouping for
      scripts, Electron, Flatpak, Snap, AppImage, Wine and Steam windows; follow Plasma's matching
      order and rules.
- [ ] **One index of applications: `maia-apps-service` + `Maia.Apps`.** Three places read
      `.desktop` files today, each its own way: Lumen's start menu (`BackendLib/AppsListModel`, read
      once: a newly installed app needs a restart of the shell), the window service
      (`apps.rs`), the notification service (`desktop.rs`). One service instead:
      - an index of id, name, generic name, icon name, categories, MIME types, Exec,
        `StartupWMClass`, `NoDisplay`, actions; translated names also through gettext domains
        (`X-Ubuntu-Gettext-Domain`): GNOME's apps are shown in English today;
      - watches the `applications` directories: installed and removed apps show at once;
      - a contract with the list and its changes, search, and "which app is this window" (the
        logic of `apps.rs` moves here);
      - icons stay names: the shell resolves them in the user's icon theme (the theme is a look);
      - order: the service and `Maia.Apps` → Lumen's start menu → the window service → the names in
        notifications and Maia Settings → later a "Default Apps" page.
- [ ] **Light/dark and the accent colour from `maia-appearance-service`** (TODO 8). Today every
      frontend keeps its own in the shared `maia.conf` (`[LumenFrontend]`, `[MaiaAppearance]`),
      Maia Settings reads Lumen's private keys, a change reaches other processes only at their next
      start, and ordinary apps (Firefox, GTK, Qt) never see it. The service owns the choice and
      **remembers the whole look for each frontend on its own**: light or dark, the accent, the
      window decoration (that one already), so that switching never spoils a frontend the user has
      set up. The active frontend's look is in force, `Maia.Appearance` gives it to every shell and
      app live, and the desktop portal (`org.freedesktop.appearance`) and KDE's colours give it to
      the other apps; switching the frontend switches to its own look.
- [ ] **Favourite apps shared by every shell** over a contract (today `FavoriteAppsService` on
      D-Bus in the shell process).
- [ ] **Mock-ups in Lumen's quick settings:** airplane mode (NetworkManager and rfkill), night light
      (KWin's night light, or the compositor's).
- [ ] **Files.** Lumen's file explorer shows a mock file system (`apps/files/MockFileSystem.js`).
      A files service: folder listing with change watching, MIME types and icon names, create,
      rename, the freedesktop trash, copy and move as jobs with progress (they would show like
      Dolphin's copies), search, recent files, drives (UDisks2). Later thumbnails and remote places.
- [x] **Notifications: files and icon actions** (2026-11-16): previews of `x-kde-urls` (open, drag,
      show in folder), icon buttons for `action-icons`; images in the body left out on purpose.
- [ ] **Notifications, what is left:** history on disk.

## 4. Maia Settings

The order follows what people look for most; each page on its service's QML module, laid out
like GNOME Settings (Ubuntu 24.04 / 26.04). Until a page exists, KDE's System Settings is the
fallback.

- [ ] Sound (with the sound service above)
- [ ] Bluetooth (with the Bluetooth support above)
- [ ] Displays: resolution, scale, arrangement, night light (KWin's output management)
- [ ] Appearance: light/dark, accent (TODO 8), fonts, icon theme, decorations
      (`maia-appearance-service`)
- [ ] Default Apps (with `maia-apps-service`)
- [ ] Mouse & Touchpad, Keyboard (layouts, shortcuts)
- [ ] Users, Date & Time, Region & Language, About
- [ ] Translations of Maia's own texts (English only until then)

## 5. Other shells

- [x] **Maia (tablet face): notification banners** (2026-11-23): a new overlay layer process, one
      banner at the top (tap, swipe up, pull down, actions, answer, files, sound, quiet over
      fullscreen). The layers share state through `Maia.CrossProcessState` (`ShellState`).
- [x] **Maia (tablet face): notification center** (2026-11-23): a panel opened by the time in the
      status button (the icons open the Control Center), stacks by application
      (`NotificationGroupsModel`), swipe to clear, an unread badge, Do Not Disturb in the Control
      Center.
- [x] **Maia (tablet face): job progress** (2026-11-23): a pill at the top like a Live Activity
      (`JobPopupsModel`: ring, pause, cancel with a confirmation, "Done"), "Activities" in the
      notification center, a ring by the clock.
- [ ] **Maia (tablet face), what is left:** dock badges, a swipe from the screen edge;
      then the rest on the same services as Lumen (dock, control center already use `Maia.Windows`,
      `Maia.Network`, `Maia.Power`).
- [ ] **Ubuntu 24.04, XPLuna, Experimental:** decide which stay. Those that stay move from the
      X11-era classes (`X11WindowManagerService`, `MWindowManagerX11`) to the services; the others go
      to an archive or stay as examples.

## 6. For developers (users do not see it)

- [ ] **Settings of a new Maia version.** Every version keeps its settings in its own directory
      (`~/.config/maia/<version>/`, by design: versions installed side by side never share them),
      so a new version starts with defaults. Offer to take over the previous version's settings
      (TODO 6).
- [ ] **A settings service** with a contract: typed key-value namespaces, watching across
      processes, permissions per frontend (TODO 7; under consideration).
- [ ] **No `unsafe` in Maia's Rust code** and `#![forbid(unsafe_code)]` in every crate (TODO 5;
      `windows/service/src/kwin.rs` still has one block, `appearance` keeps its inotify FFI in an
      allowed module).
- [ ] **Small fixes:** Maia frontend `shell/Main.qml` logs `appLauncherWindow`, which does not exist;
      `MaiaServerApp/main.cpp` in client mode puts the installed QML modules before
      `QML_IMPORT_PATH` (the shell's `QmlGui` does it the other way, correctly).
- [ ] **Public C++ API** of the QML modules (installed headers, `find_package`), once a program
      outside this repository needs it.
- [ ] **A timer service** (the original proof of concept: Lumen's timer keeps running when the
      frontend changes). The contracts and the Qt bridge it was to prove are proven by the services
      above; do it when Lumen's timer needs it.

## 7. Later: security and generated interfaces

- [ ] Landlock and systemd sandboxing for every service
- [ ] Generated widgets in their own process (bubblewrap/Landlock), a restricted QML engine
      (allowed imports, no network, only granted contracts)
- [ ] A safe set of components (Lumen's building blocks) documented for AI
- [ ] Generation loop: prompt → QML → `qmllint` → sandboxed preview → approval
- [ ] Maia's own portal backend (a file chooser in Lumen's style)
- [ ] A "who has access to what" page, with revoking
- [ ] Documentation of the contracts and a frontend template for shell authors

---

## Principles

- **Services own the logic and the data, shells only show it.** Rust services
  (`Maia/services/<area>/`), QML shells (`Maia/frontends/`); a shell that restarts or is switched
  finds everything as it was.
- **Cap'n Proto contracts** between them (`contract/*.capnp`), over Unix sockets in
  `$XDG_RUNTIME_DIR/maia/`: the whole state first, then changes; results as values; one socket per
  role (a sandbox gets only what it needs).
- **D-Bus only to integrate with the system** and with existing apps (NetworkManager, UPower,
  logind, `org.freedesktop.Notifications`, ...): services are thin adapters on these standards,
  they do not reinvent the system.
- **QML modules give data and state, never the look.** Icons, wording and colours belong to the
  shell or the app. A module names its domain (`Maia.Power`), never the process behind it; a part for
  one kind of user is a sub-module (`Maia.Notifications.Center` for shells, `.Settings` for Maia
  Settings).
- **Never block the GUI thread.** Cap'n Proto runs in its own thread in the Qt modules; changes come
  in batches, at most one per frame; slow work (files, images) happens off the GUI thread.
- **Owner of the knowledge decides.** No central "manager" service: e.g. the power service sends its
  own battery notifications through the notification service.
- **Tests for every service and module**, against private buses and sockets; never the user's
  session or settings. Shells are checked in a nested session (`README.md`, "Contribution").
