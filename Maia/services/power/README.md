# maia-power-service

The power state of a Maia session: the batteries (the computer's and devices' such as a mouse or
headphones), the brightness of the screen and of the keyboard backlight, and the power profile. The
only process of Maia that reads and changes them; shells, Maia Settings and apps use it through the
`Maia.Power` QML module.

It uses the system's own services, nothing of a desktop environment:

| What | Source | How |
|---|---|---|
| Batteries, the charger, the lid | UPower (system D-Bus) | every signal of UPower, then everything read again (`system/upower.rs`) |
| Keyboard backlight | UPower's `KbdBacklight` | `GetBrightness`, `SetBrightness`, when the machine has one |
| Screen brightness | `/sys/class/backlight` | read from sysfs; written through logind's `Session.SetBrightness` (no root, only the active session), the attribute itself as a fallback (`system/backlight.rs`) |
| Power profile | power-profiles-daemon | `ActiveProfile`, `HoldProfile` / `ReleaseProfile` (`system/profiles.rs`) |

powerdevil (KDE) still runs in the session for what this service does not do yet: dimming and
turning the screen off when idle, the lid, the brightness keys, the critical battery action. Both
see the same sysfs value, so they never disagree for long: changes made by others are read again
every second (a write to the attribute sends no kernel event), and backlight devices that appear or
change by hardware keys are seen at once through the kernel's uevents.

```
UPower ────────────┐                                 ┌─► Power (singleton): battery, brightness, profile
/sys + logind ─────┼─► backend ──► hub (rpc.rs) ──Cap'n Proto──► BatteriesModel, DisplaysModel
power-profiles ────┘   system/     state, events,    power.capnp └─► ProfileHold
                       or fake.rs  50 ms throttle
```

| Directory | What it is |
|---|---|
| `contract/power.capnp` | The contract: the state (batteries, displays, keyboard, profiles), events, and the requests |
| `service/` | The service (Rust): `model.rs` the state and its rules, `system/` the real sources, `fake.rs` a simulated laptop, `events.rs` notifications, `rpc.rs` Cap'n Proto |
| `qml/` | The QML module `Maia.Power`: `Power`, `BatteriesModel`, `DisplaysModel`, `ProfileHold` |

## The contract in short

- `watch(listener)`: the whole state first (snapshot), then each change: `statusChanged` (the charger,
  the lid, the computer's battery as one), `batteryChanged` / `batteryRemoved`, `displayChanged` /
  `displayRemoved`, `keyboardChanged`, `profilesChanged`, and `event` for notifications
  (`chargerConnected`, `chargerDisconnected`, `batteryLow`, `batteryCritical`, `batteryAction`,
  `batteryFull`, `deviceBatteryLow`).
- `control()`: `setBrightness(display, 0..1)`, `stepBrightness(display, ±steps of 5 %)`,
  `setKeyboardBrightness(0..1)`, `setProfile(profile)`, `holdProfile(profile, reason, app)` → a
  capability that holds the profile until it is dropped (or its client disconnects).
- Brightness never goes below one hardware step (some panels go black at 0). Requests while one is
  being written are coalesced: only the newest is written next, every request is answered.
- What a machine lacks is a state, not an error: no battery (`summary.present = false`), no
  backlight (no display), no power-profiles-daemon (`profiles.available = false`).

## In QML

```qml
import Maia.Power

Text { visible: Power.hasBattery; text: Math.round(Power.batteryPercentage) + " %" }
Slider { enabled: Power.brightnessAvailable; value: Power.brightness; onMoved: Power.brightness = value }
ComboBox { model: Power.profiles; onActivated: Power.profile = currentValue }
ProfileHold { active: building; profile: Power.Performance; reason: qsTr("Compiling") }
Connections { target: Power; function onEvent(kind, battery, percentage) { if (kind === Power.BatteryLow) … } }
```

`Power.brightness` may be set on every movement of a slider: the module shows the value at once,
sends at most every 40 ms, and does not move the slider back to older echoes of the service while
it is dragged.

## Environment

| Variable | |
|---|---|
| `MAIA_POWER_BACKEND` | `system` (default) or `fake`: a simulated laptop, nothing reaches the machine |
| `MAIA_POWER_SOCKET` | the socket (default `$XDG_RUNTIME_DIR/maia/power-$WAYLAND_DISPLAY.sock`) |
| `MAIA_POWER_SYSFS_ROOT` | where sysfs is (default `/sys`) |

## Tests

- `cargo test` in `service/`:
  - unit tests: UPower's numbers, the brightness arithmetic, battery icons, events, the choice of the
    backlight device, coalescing, the parsing of UPower's and power-profiles-daemon's properties;
  - `tests/service.rs`: the service over a real Cap'n Proto connection with the fake backend (the
    charger and a draining battery with their events, the slider and the keys, devices coming and
    going, the keyboard, profiles and holds, a hold ending with its client, refusals);
  - `tests/system.rs`: the real system backend against stand-ins of UPower, power-profiles-daemon and
    logind on a private `dbus-daemon`, with a sysfs directory of the test (logind's SetBrightness,
    changes made by others, a session that may not change the screen, UPower's signals, devices
    added and removed, the daemon going away and coming back, a machine without UPower).
- `tst_power` (CTest `maia-power-qml`): `Maia.Power` against the real service with the fake backend.
- A nested session (`run_maia_nested_wayland.sh`) uses the fake backend: logind changes the screen only
  for the active session, and the nested one is a window inside it.
