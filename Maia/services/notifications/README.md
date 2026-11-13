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
| `Notifier` (Cap'n Proto, `notifications-<display>.sock`) | Maia's programs and services (`Maia.Notifications`; maia-power-service's battery warnings) | `notify` → a handle (`update`, `close`) and a listener that hears only its own notification |
| `NotificationCenter` (Cap'n Proto, `notifications-center-<display>.sock`) | shells (`Maia.Notifications.Center`) | the list (snapshot, then batches), actions with an activation token, replies, dismiss, the end of a popup, do not disturb |

Two sockets because the center sees the content of every notification and a sender only its own:
a sandbox can later be given the first one only.

| Directory | What it is |
|---|---|
| `contract/notifications.capnp` | The contract, with its rules |
| `service/` | The service (Rust): `model.rs` the list and its rules, `markup.rs` the safe body, `image.rs` images as files, `hub.rs` the shared state and the batches, `dbus.rs` the D-Bus door, `rpc.rs` the Cap'n Proto doors |
| `qml/common/` | What both QML modules share: the contract's values, `ServiceLink` (Cap'n Proto in its own thread) |
| `qml/notifications/` | `Maia.Notifications`, for programs that send |
| `qml/center/` | `Maia.Notifications.Center`, for shells that show |

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
```

A shell:

```qml
import Maia.Notifications.Center

ListView { model: NotificationPopupsModel { maximumCount: 3; paused: hover.hovered } … }   // the popups now
ListView { model: NotificationsModel {} … }                                         // the center
Button { onClicked: NotificationCenter.invokeAction(model.notificationId, "default", Window.window) }
ToggleTile { checked: NotificationCenter.doNotDisturb; onToggled: NotificationCenter.doNotDisturb = checked }
```

## Environment

| Variable | |
|---|---|
| `MAIA_NOTIFICATIONS_SOCKET` | the senders' socket (default `$XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock`) |
| `MAIA_NOTIFICATIONS_CENTER_SOCKET` | the shells' socket (default `…/notifications-center-$WAYLAND_DISPLAY.sock`) |
| `MAIA_NOTIFICATIONS_DBUS` | `0`: no D-Bus door (tests) |

The image directory is named after `$WAYLAND_DISPLAY` and emptied at start: a test or a second
instance needs its own display name.

## Tests

- `cargo test` in `service/`: unit tests (ids, replacing, limits, do not disturb, the markup, the
  images, the hints); `tests/dbus.rs` against a private `dbus-daemon` as an application talks to it
  (actions with the token in order, replies, signals only to the sender, inhibitions ending with
  their application, pixels as a PNG file, a flood of 1000); `tests/notifier.rs` the Cap'n Proto doors
  (handles, a reconnecting shell, do not disturb ending by itself, low urgency).
- `tst_notifications` (CTest `maia-notifications-qml`): both QML modules against the real service:
  popups and their clocks (pause, the maximum, critical), actions and replies back to the sender,
  updates, a restart of the service, the flood and the GUI thread's longest stall.
- maia-power-service's `tests/notify.rs`: the battery warnings reach a stand-in of the Notifier.

Not yet: `org.kde.JobViewServer` (the progress of file copies), sounds, history on disk.
