# maia-session-service

The main process of a Maia session. The session script (`run_maia_kwin.sh`, `run_maia_wayfire.sh`)
prepares the environment and ends with `exec` into it; the service then:

1. starts the compositor and waits until it reports its display (the ready helper),
2. starts the processes of `session.toml` in their order: kglobalacceld (Wayfire), KDE's units,
   Maia's services, the shell (`appMaiaServer`),
3. starts a child that ended again after a wait (1 s, doubling up to 30 s), gives up after the
   limits of `session.toml` (the shell: 5 crashes in 2 minutes end the session),
4. ends the session in order when asked (logout, reboot, power off), on SIGTERM / SIGHUP, on a
   shutdown from outside, or when the compositor ended: the shell first, then the other children,
   KDE's units, the compositor last.

It is the only part of Maia that talks to systemd-logind (power off, reboot, sleep, what the system
offers). Shells and apps reach it over Cap'n Proto through the `Maia.Session` QML module.

```
SDDM
 └─ run_maia_kwin.sh / run_maia_wayfire.sh            (bash: the environment, dbus-run-session)
     └─ exec maia-session-service --compositor kwin|wayfire
         ├─ kwin_wayland_wrapper --xwayland "<ready helper>"   or   wayfire -c ~/.config/maia/<v>/wayfire.ini
         │      └─ maia-session-service --compositor-ready     (reports WAYLAND_DISPLAY, DISPLAY, …)
         ├─ kglobalacceld                                (Wayfire only)
         ├─ systemctl --user start plasma-kwallet-pam, -polkit-agent, -powerdevil, -kaccess
         ├─ maia-windows-service, maia-network-service, maia-appearance-service (KWin only)
         └─ appMaiaServer                                (started again after a crash)
```

| Directory | What it is |
|---|---|
| `contract/session.capnp` | The contract: state, what the system offers, the children; logout, reboot, power off, sleep, restartChild |
| `service/` | The service (Rust): `session.rs` the event loop, `manifest.rs` session.toml, `policy.rs` restarts, `procs.rs` processes, `power.rs` logind, `rpc.rs` Cap'n Proto, `ready.rs` the ready helper |
| `qml/` | The QML module `Maia.Session`: `Session` (singleton), `SessionChildrenModel` |
| `../../DeployFiles/etc/maia/session.toml` | What a session runs; installed to `<prefix>/etc/maia/session.toml`, one per Maia version |

## The ready helper

The services and the shell need `WAYLAND_DISPLAY` and `DISPLAY`, and the compositor chooses them
(KWin's wrapper takes a free socket, Wayfire has no option for it). So the compositor starts
`maia-session-service --compositor-ready`, which inherits its environment, hands the display to the
service through `$MAIA_SESSION_SOCKET` and ends:

- KWin: as an application on its command line (`ready = "argument"` in session.toml). Unlike
  `--exit-with-session`, its end does not end KWin; after a crash KWin's wrapper starts KWin again on
  the same sockets, and the helper reports again (noted in the log).
- Wayfire: from `[autostart]` (`ready = "autostart"`): the template has `maia = "$MAIA_SESSION_SCRIPT"`,
  and the service sets `MAIA_SESSION_SCRIPT` to the helper.

No report within `ready_timeout` (20 s): the session ends with a message in the log.

## Processes

- Every child runs in its own process group and gets SIGTERM when the service dies
  (`PR_SET_PDEATHSIG`): nothing outlives the session.
- The service is a child subreaper: processes orphaned inside the session (Wayfire's autostart forks
  twice; applications started by maia-windows-service) are reaped by it and ended with the session.
- The output of every child goes to the session log line by line, with its name in front:
  `[maia-network-service] …`. The log stays where the session script puts it,
  `~/maia_<v>_kwin_session.log` (or `_wayfire_`); appMaiaServer also writes `~/maia_<v>_server.log`.
- Display variables (`WAYLAND_DISPLAY`, `DISPLAY`, `XAUTHORITY`, `WAYFIRE_SOCKET`) reach the children
  only from the compositor's report, never from the service's own environment (in a nested session
  that is the outer session's). They and the session's variables are exported to D-Bus activation
  (and to systemd --user, outside test mode) before anything else starts.

## Ending

- **Logout:** the answer comes at once; then the shell (SIGTERM, SIGKILL to its group after its
  `stop_timeout`), the other children together, KDE's units (`systemctl --user stop`), what else lives
  under the service, the compositor; the service exits with 0.
- **Reboot, power off:** logind is asked first, while the compositor and the polkit agent run (with
  another user logged in, polkit asks for the administrator's password). Refused or cancelled: the
  session goes on and the client gets `notAllowed`. Accepted: the session ends as for a logout.
- **Suspend, hibernate:** only logind; `PrepareForSleep` turns the state into `sleeping` and back.
- A second SIGTERM or SIGINT while ending kills everything at once.

## Environment

| Variable | |
|---|---|
| `MAIA_SESSION_MANIFEST` | session.toml to read (default `<prefix>/etc/maia/session.toml`) |
| `MAIA_SESSION_SOCKET` | the socket (default `$XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock`); every child gets it |
| `MAIA_SESSION_BACKEND` | `logind` (default) or `fake`: power actions only logged, nothing reaches the machine |
| `MAIA_SESSION_FAKE_LOGIND=deny` | the fake refuses every action (a cancelled password dialog) |
| `MAIA_SESSION_TEST=1` | next to a real session: no systemd --user units, no export to systemd |
| `MAIA_PREFIX`, `MAIA_VERSION`, `MAIA_CONFIG_DIR` | for session.toml; set by the session script, derived when unset |

`--without <name>` leaves a process of session.toml out (`run_maia_nested_wayland.sh --compositor-only`
runs the session without the shell, to start it from a debugger).

## Tests

- `cargo test` in `service/`: session.toml (also the installed one), the restart waits and limits,
  and the service as a program with a fake compositor, fake processes and the fake logind
  (`tests/service.rs`): the order of the start and the end, the environment, a restarted service,
  a shell that keeps crashing, power off accepted and refused, a compositor that never reports,
  a process that ignores SIGTERM, SIGTERM, nothing left after the service is killed.
- `tst_session` (CTest `maia-session-qml`): `Maia.Session` against the real service.
- A nested session: `run_maia_nested_wayland.sh` (compositor `kwin-nested`, fake logind, its own
  D-Bus); kill appMaiaServer and watch it come back with the windows still open.
