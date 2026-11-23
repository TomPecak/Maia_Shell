# maia-notifications-service

The notification server of a Maia session. It keeps the session's notifications, whoever sent them
and whichever shell shows them: a shell that restarts, or is switched for another, finds the list as
it was. A shell only draws.

```
applications ──D-Bus: org.freedesktop.Notifications──┐  (+ KDE: inline reply, Inhibit)
                                                      ├──► hub: the list, the rules ──Cap'n Proto──► shells
Maia's programs ──Cap'n Proto: Notifier──────────────┘     batches, ≤ 1 per frame   NotificationCenter
           ▲                                                                           (Maia.Notifications.Center)
           └─────────── ActionInvoked, Replied, Closed (to the sender only) ◄──────────┘
```

| Door | For | What |
|---|---|---|
| `org.freedesktop.Notifications` (session D-Bus) | every application: `notify-send`, libnotify, KNotification, Flatpak apps through their portal | the [specification](https://specifications.freedesktop.org/notification-spec/) 1.2: `Notify`, `CloseNotification`, `GetCapabilities`, `GetServerInformation`, the signals; KDE's `Inhibit`/`UnInhibit`/`Inhibited`, `NotificationReplied`, hints `x-kde-*` |
| `Notifier` (Cap'n Proto, `notifications-<display>.sock`) | Maia's programs and services (`Maia.Notifications`; maia-power-service's battery warnings) | `notify` → a handle (`update`, `close`) and a listener that hears only its own notification; `startJob` → a job handle (`update`, `finish`, `canceled`) and a listener of the user's pause and cancel |
| `NotificationCenter` (Cap'n Proto, `notifications-center-<display>.sock`) | shells (`Maia.Notifications.Center`) | the list (snapshot, then batches), actions with an activation token, replies, dismiss, the end of a popup, do not disturb, the shells' settings (the lock screen) |
| `NotificationSettings` (Cap'n Proto, `notifications-settings-<display>.sock`) | Maia Settings (`Maia.Notifications.Settings`) | the rules: do not disturb, notifications on the lock screen, each application on or off |

Three sockets, one per role: the center sees the content of every notification, a sender only its
own, the settings none (only which applications send). A sandbox can later be given the first one
only.

| Directory | What it is |
|---|---|
| `contract/notifications.capnp` | The contract, with its rules |
| `service/` | The service (Rust): `model.rs` the list and its rules, `markup.rs` the safe body, `image.rs` images as files, `hub.rs` the shared state and the batches, `dbus.rs` the D-Bus door, `rpc.rs` the Cap'n Proto doors |
| `qml/common/` | What both QML modules share: the contract's values, `ServiceLink` (Cap'n Proto in its own thread) |
| `qml/notifications/` | `Maia.Notifications`, for programs that send |
| `qml/center/` | `Maia.Notifications.Center`, for shells that show |
| `qml/settings/` | `Maia.Notifications.Settings`, for Maia Settings |

## The rules

- **Only data.** The texts are the senders' (a notification is a message for people); how it looks is
  the shell's. The body is made safe: `<b> <i> <u> <a href> <br/>` stay, any other tag goes with its
  text kept, `<` and `&` that are no markup become entities.
- **Images are files.** Pixels sent over D-Bus (`image-data`) are scaled down to at most 512 px and
  written as PNG into `$XDG_RUNTIME_DIR/maia/notifications-<display>/` (memory, private); paths become
  `file://` URLs. A new image gets a new URL. The shell decodes a small file asynchronously
  (`Image { asynchronous: true; sourceSize: … }`), and messages stay small.
- **Popups.** The service decides what pops up: not during do not disturb (critical notifications
  still do), not low urgency (into the list only, as Plasma does by default). The shell counts how
  long (`NotificationPopupsModel`: the sender's timeout or the shell's default, paused while hovered,
  critical ones and timeout 0 until closed) and reports the end with `expire`; the notification
  stays in the list unless it is transient. While the user works fullscreen on the popups' screen
  (`suppressed`, from Maia.Windows' `FullscreenState`) only critical ones pop up, the others go
  into the list at once and do not come back afterwards. One process of a shell shows popups.
- **Sounds.** A sender asks for one by name (`sound-name`, of the freedesktop sound theme) or file
  (`sound-file`, a `file://` URL in the contract); the name stays a name, as an icon name does: the
  shell's sound theme decides how it sounds. The shell plays it when the popup appears
  (`NotificationPopupsModel.popupShown`, then `Maia.Sounds`), so do not disturb, fullscreen and low
  urgency are silent too. No default sound: KDE applications play theirs through KNotification,
  a default one would ring twice (as Plasma does).
- **Actions.** The shell asks the compositor for an xdg-activation token for the click, the service
  hands it to the sender (on D-Bus the signal `ActivationToken` before `ActionInvoked`), so that the
  application may raise its window. After an action or a reply the notification closes, unless it is
  resident. Signals go to the sender only, never to the whole bus.
- **Do not disturb**: the user's (with an end time, e.g. "for 30 minutes") or an application's
  (`Inhibit`, e.g. a presentation; it ends when the application leaves the bus).
- **Limits.** 200 notifications (the oldest go first, critical ones last; their senders hear
  `Closed(other)`), 8 actions, 400 characters of title, 8000 of text.
- **The list lives as long as the session**; nothing is written to disk.

## Fast and never blocking

- One thread, tokio `current_thread`: work per notification is microseconds. `Notify` answers at
  once; an image is written on a blocking thread and the notification is shown when it is ready.
- Changes reach the shells in **batches, at most one per frame (16 ms)**: a flood of notifications is
  one model update per frame, with the latest content of each notification only.
- In the QML modules Cap'n Proto runs in its own thread; a batch is read into Qt values there and
  applied in the GUI thread as a whole (one insertion, contiguous removals). Answers to a sender go
  to their `Notification` object directly, together per turn of the loop.
- Measured (`tst_notifications`, debug build): 1000 notifications at once, all shown after ~120 ms,
  the GUI thread never stalls for more than 2 ms. On D-Bus (`tests/dbus.rs`): 1000 `Notify` calls
  answered in ~0.2 s, shown to the shell in 9 batches.

## In QML

A program:

```qml
import Maia.Notifications

Notification {
    id: done
    summary: qsTr("Backup finished")
    body: qsTr("<b>%1</b> files copied").arg(count)
    iconName: "drive-harddisk"
    actions: [{ key: "default", label: "" }, { key: "open", label: qsTr("Open folder") }]
    onActionInvoked: key => { openFolder(); done.activate(window) }   // raises the window
}
… done.send()        // shows it; again: replaces its content (a progress)

Notification { summary: qsTr("Export finished"); urls: [videoUrl] }   // a preview, open, drag
Notification { actionIcons: true; actions: [{ key: "media-playback-pause", label: qsTr("Pause") }] }
```

A long operation, shown with its progress like a copy in Dolphin:

```qml
Job {
    id: export
    title: qsTr("Exporting")
    killable: true
    processedBytes: exporter.written      // the percent follows from the bytes
    totalBytes: exporter.size
    destination: folderUrl                // "Open folder" when it is done
    onCancelRequested: { exporter.stop(); export.cancel() }
}
… export.start()   …   export.finish()   // or finish(qsTr("The disk is full"))
```

A shell:

```qml
import Maia.Notifications.Center

ListView { model: NotificationPopupsModel { maximumCount: 3; paused: hover.hovered } … }   // the popups now
ListView { model: NotificationsModel {} … }                                         // the center
ListView { model: NotificationGroupsModel { id: groups; seenUntil: lastLook } … }   // or stacked by application
Badge { count: groups.unseen }                                                      // what came since
Button { onClicked: NotificationCenter.invokeAction(model.notificationId, "default", Window.window) }
ToggleTile { checked: NotificationCenter.doNotDisturb; onToggled: NotificationCenter.doNotDisturb = checked }
```

## Environment

| Variable | |
|---|---|
| `MAIA_NOTIFICATIONS_SOCKET` | the senders' socket (default `$XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock`) |
| `MAIA_NOTIFICATIONS_CENTER_SOCKET` | the shells' socket (default `…/notifications-center-$WAYLAND_DISPLAY.sock`) |
| `MAIA_NOTIFICATIONS_SETTINGS_SOCKET` | the settings' socket (default `…/notifications-settings-$WAYLAND_DISPLAY.sock`) |
| `MAIA_NOTIFICATIONS_SETTINGS` | the settings file (default `$MAIA_CONFIG_DIR/maia-notifications-service.json`); tests must set it |
| `MAIA_NOTIFICATIONS_DBUS` | `0`: no D-Bus door (tests) |
| `MAIA_NOTIFICATIONS_JOBS` | `0`: no job server (KIO shows its own progress dialog) |

The image directory is named after `$WAYLAND_DISPLAY` and emptied at start: a test or a second
instance needs its own display name.

## Tests

- `cargo test` in `service/`: unit tests (ids, replacing, limits, do not disturb, the markup, the
  images, the hints); `tests/dbus.rs` against a private `dbus-daemon` as an application talks to it
  (actions with the token in order, replies, signals only to the sender, inhibitions ending with
  their application, pixels as a PNG file, a flood of 1000); `tests/notifier.rs` the Cap'n Proto doors
  (handles, a reconnecting shell, do not disturb ending by itself, low urgency); `tests/jobs.rs`
  jobs over D-Bus as KJobWidgets and KIO's probe; `tests/maia_jobs.rs` jobs of Maia's programs
  (pause and cancel to the program alone, a dropped handle fails the job); `tests/settings.rs` the
  settings door (a turned off application, the lock screen's flag, the file across a restart,
  declared applications, a shell on an older contract).
- `tst_notifications` (CTest `maia-notifications-qml`): both QML modules against the real service:
  popups and their clocks (pause, the maximum, critical), actions and replies back to the sender,
  updates, a restart of the service, the flood and the GUI thread's longest stall; a program's Job
  (progress, pause and cancel, failing, back after a restart of the service). `tst_jobs`: jobs of
  a QtDBus client in JobsModel.
- maia-power-service's `tests/notify.rs`: the battery warnings reach a stand-in of the Notifier.

## Files and icon actions

- **Files** (`x-kde-urls`, KDE's extension, which KNotification sends only to a server that lists it:
  Spectacle's screenshot, KDE Connect's received files; Maia's programs: `Notification.urls`). The
  service keeps URLs only (`model::urls`: a path becomes `file://`, no `javascript:`/`data:`, at most
  32). The shells' module reads each file once, off the GUI thread (`qml/common/NotificationFiles`):
  name, MIME type by name, its icon names, and a preview: a fresh picture of the freedesktop
  thumbnail cache, else the file itself when it is an image; role `files`. Lumen shows one file
  with a preview large, else rows; a click opens, a drag hands the file to another application,
  a button opens its folder.
- **Icon actions** (`action-icons`, the freedesktop specification): the actions' keys are icon
  names (a media player's ⏮ ⏸ ⏭); the labels become tooltips. Lumen uses its own glyph when it has
  one, else the icon theme's, else the label.
- Not `body-images`: images in the body are dropped on purpose (a remote one would tell the sender
  that the message was read); a picture goes in the `image` hint.

## Settings

Kept across sessions in `$MAIA_CONFIG_DIR/maia-notifications-service.json` (`settings.rs`; named
after the service, its only writer; written a moment after a change, as a whole new file renamed
over the old):

| Setting | Who applies it |
|---|---|
| Do not disturb (and until when) | the service: no popups, no sounds; the notifications go into the list; critical ones still pop up. The same state as the shell's quick settings tile |
| Notifications on the lock screen | the shells (they draw the lock screen): the service keeps the choice, `NotificationCenter.lockScreenNotifications` gives it to them |
| Each application on or off | the service: a turned off application's notifications are dropped (no list, no popup, no sound); its sender gets an id and hears "closed" 100 ms later. Jobs are not affected |

The applications are those that have sent a notification (remembered; known by their desktop
entry, else by the name they send) and those that declare it (`desktop.rs`: a desktop entry with
`X-GNOME-UsesNotifications=true`, a KDE `.notifyrc` naming its `DesktopEntry`), named by their desktop
entry in the session's language (`Name[pl]`; names translated by gettext domains, as Ubuntu does for
GNOME's applications, are not read yet).

```qml
import Maia.Notifications.Settings

LSwitch { checked: NotificationSettings.doNotDisturb; onToggled: NotificationSettings.doNotDisturb = checked }
Repeater { model: AppNotificationsModel {}       // sorted by name
           LSwitch { checked: model.enabled; onToggled: NotificationSettings.setAppEnabled(model.key, checked) } }
```

## Jobs

The progress of long operations of KDE applications (a copy in Dolphin, an archive in Ark) comes
through `org.kde.JobViewServer` (`dbus_jobs.rs`, the interfaces of Plasma's notification applet),
that of Maia's programs through `Notifier.startJob` (QML: `Job`), and is a second list next to the notifications (`jobs.rs`, Plasma's rules: shown after 0.5 s, the
progress at most every 250 ms, finished and failed jobs kept until dismissed, canceled ones gone, a
cancel without an answer ends the job after 2 s, a job whose application quits has failed; a
Maia program's pause and cancel go to its JobListener, a D-Bus one's to its JobView). Shells
get it as `JobsModel` (the list) and `JobPopupsModel` (what is on screen now: the oldest running job,
a moment more after it ends, `hide()`, `paused`, `suppressed`) and act with
`NotificationCenter.cancelJob / suspendJob / dismissJob`. An update tells a view only the roles that
changed. The Maia frontend shows a pill with a ring at the top of the screen; Lumen
shows a card with the progress above the popups, keeps it a few seconds after the end ("Open
folder"), lists the jobs in the notification center and turns a ring by the clock.

While the service owns `org.kde.kuiserver`, KIO reports to it instead of showing its own progress
dialog; `MAIA_NOTIFICATIONS_JOBS=0` leaves the names to nobody (KIO's dialog again). Before it
reports a job KIO asks the server (KDynamicJobTracker): `/JobViewServer` must introspect
`org.kde.JobViewServerV2` and answer `org.kde.kuiserver.requiresJobTracker()` with false; the same
interface tells file managers where running jobs write to (`jobUrlsChanged`).

`tools/fake-job.py` reports a pretend copy the way KIO does for Dolphin (pause and cancel work):

    Maia/services/notifications/tools/fake-job.py --seconds 20 --size 15000

Not yet: history on disk.
