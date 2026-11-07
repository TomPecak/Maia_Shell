#!/usr/bin/env python3
"""The architecture diagrams of Maia's services, one SVG per service.

    python3 <path>/service_diagrams.py              (from any directory)

writes maia-windows-service.svg, maia-network-service.svg and maia-appearance-service.svg
into the current directory (the repository keeps them in Maia/services/<service>/docs/). Every diagram has the same layout, so one explains the others:

    left: what the service uses        middle: the service process      right: the Maia side
    (system processes, buses, files)   (its modules, the contract)      (the QML module, its users)
    bottom: the API (the contract's interfaces and methods), where the code is, the legend

Change the descriptions here when a service changes; svgkit.py draws.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from svgkit import (PROCESS_CHILD, PROCESS_CLIENT, PROCESS_MAIA, PROCESS_SYSTEM, Rect, Svg)  # noqa: E402


W = 1900
LX, LW = 30, 470            # left column
MX, MW = 600, 690           # the service's process frame
AX, AW = 618, 300           # its left sub-column (modules that talk to the system)
BX, BW = 972, 300           # its right sub-column (modules that talk to clients)
RX, RW = 1390, 480          # right column
LANE_L = [512, 530, 548, 566, 584]
LANE_M = [929, 939, 949, 959]
LANE_R = [1304, 1322, 1340, 1358, 1376]
TOP = 100
GAP = 14


def header(s, title, subtitle):
    s.text(30, 44, title, size=24, weight="bold")
    s.text(30, 70, subtitle, size=14, fill="#475569")
    s.column_title(LX, TOP, LW, "What the service uses", "system processes, buses and files")
    s.column_title(MX, TOP, MW, "The service", "one process per session, one thread (tokio); nothing blocks")
    s.column_title(RX, TOP, RW, "The Maia side", "the QML module and the processes that load it")


def stack(s, x, y, w, items):
    """Cards one under another; items: (title, kind, path, lines). Returns (rects, bottom)"""
    rects = []
    for title, kind, path, lines in items:
        r = s.card(x, y, w, title, kind, lines, path)
        rects.append(r)
        y = r.bottom + GAP
    return rects, y - GAP


def frame_height(start, *bottoms, pad=16):
    return max(bottoms) - start + pad


def finish(s, y, api_columns, repo_rows, out):
    """The bottom panels: API, where the code is, legend. Writes the file."""
    y += 40
    api_w = 1240
    col_w = api_w / len(api_columns)
    # Measure first (panels are drawn under their content)
    probe = Svg(W)
    heights = []
    for column in api_columns:
        heights.append(sum(probe.api_block(0, 0, col_w - 30, *block) for block in column))
    api_h = 60 + max(heights)
    legend_h = 50 + probe.legend(0, 0) + 10
    repo_h = 56 + 22 * len(repo_rows)

    s.panel(Rect(30, y, api_w, api_h), "API: the functions the service offers (Cap'n Proto contract)")
    for i, column in enumerate(api_columns):
        cy = y + 58
        for block in column:
            cy += s.api_block(30 + 20 + i * col_w, cy, col_w - 30, *block)

    ry = y + api_h + 20
    s.panel(Rect(30, ry, api_w, repo_h), "Where the code is (repository)")
    for i, (path, text) in enumerate(repo_rows):
        s.text(50, ry + 56 + 22 * i, path, size=11.5, fill="#0f172a", mono=True)
        s.text(50 + 560, ry + 56 + 22 * i, text, size=12, fill="#334155")

    s.panel(Rect(1300, y, 570, max(legend_h, api_h + 20 + repo_h)), "Legend")
    s.legend(1320, y + 48)

    height = max(y + legend_h, ry + repo_h) + 30
    path = os.path.join(os.getcwd(), out)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.render(height))
    print("wrote", path)


# ---------------------------------------------------------------------------------------------
# maia-windows-service
# ---------------------------------------------------------------------------------------------

def windows():
    s = Svg(W)
    header(s, "maia-windows-service: the window list of a Maia session",
           "KWin knows every window; the service makes one list of them for every taskbar and dock, and carries out what they ask "
           "(activate, close, minimize, start an app). Repository: Maia/services/windows/")
    y0 = TOP + 50

    # --- Left ---
    kwin = Rect(LX, y0, LW, 0)
    (proto, icons), b = stack(s, LX + 14, y0 + 52, LW - 28, [
        ("Plasma window management", "system", "Wayland: org_kde_plasma_window_management", [
            "every window: title, app id, pid, states, geometry,",
            "virtual desktops; commands: activate, close, minimize ...",
            "a privileged protocol: KWin gives it to trusted clients"]),
        ("Window icons", "system", None, ["the bitmap icon of a window, sent through a pipe"]),
    ])
    kwin.h = frame_height(y0, b)
    s.process(kwin, "kwin_wayland", "the compositor (system)", PROCESS_SYSTEM)
    y = kwin.bottom + 26
    entries = s.file(LX, y, LW, "Desktop entries", [
        "Name, Icon, Exec, StartupWMClass: which application a",
        "window belongs to, and how to start it again"],
        ["$XDG_DATA_HOME/applications/*.desktop", "$XDG_DATA_DIRS/*/applications/*.desktop"])
    y = entries.bottom + 20
    proc = s.file(LX, y, LW, "/proc/<pid>/exe", [
        "the program of a window's process: the last resort",
        "when the app id matches no desktop entry"])
    y = proc.bottom + 26
    started = Rect(LX, y, LW, 88)
    s.process(started, "Started applications", "child processes", PROCESS_CHILD)
    s.text(LX + 16, y + 62, "own process group: they outlive a restart of the service", size=12, fill="#334155")

    # --- Middle ---
    svc = Rect(MX, y0, MW, 0)
    (kwinrs, apps, launch, backend), a_b = stack(s, AX, y0 + 72, AW, [
        ("kwin.rs", "rust", "service/src/kwin.rs", [
            "the KWin backend: speaks the protocol,",
            "turns its events into whole Window values,",
            "carries out Commands"]),
        ("apps.rs", "rust", "service/src/apps.rs", [
            "which application a window belongs to",
            "(desktop entries; like KDE's TaskTools)"]),
        ("launch.rs", "rust", "service/src/launch.rs", [
            "starts applications from Exec= (quoting of",
            "the desktop entry spec), reaps them"]),
        ("backend.rs", "rust", "service/src/backend.rs", [
            "BackendEvent and Command: what a",
            "compositor backend and the service exchange"]),
    ])
    (model, throttle, rpc, main), b_b = stack(s, BX, y0 + 72, BW, [
        ("model.rs", "rust", "service/src/model.rs", [
            "the window list: order, what changed,",
            "last activation time (pure logic, no I/O)"]),
        ("throttle.rs", "rust", "service/src/throttle.rs", [
            "at most one change per window and frame",
            "(~16 ms): a dragged window moves every frame"]),
        ("rpc.rs", "rust", "service/src/rpc.rs", [
            "WindowService, WindowControl: a snapshot,",
            "then the changes to every listener; icons"]),
        ("main.rs", "rust", "service/src/main.rs", [
            "the socket $XDG_RUNTIME_DIR/maia/",
            "windows-$WAYLAND_DISPLAY.sock (one per session)"]),
    ])
    svc.h = frame_height(y0, a_b, b_b)
    s.process(svc, "maia-windows-service", "Maia service (Rust)", PROCESS_MAIA,
              "Maia/services/windows/service/   ->   <prefix>/libexec/maia-windows-service")
    contract = s.card(MX, svc.bottom + 20, MW, "windows.capnp", "contract", [
        "the contract: the Rust code (build.rs) and the C++ code (CMake) are generated from it",
        "WindowService, WindowListener, WindowControl, Window"], "Maia/services/windows/contract/windows.capnp")

    # --- Right ---
    lib = Rect(RX, y0, RW, 0)
    (conn, source, tasks), lb = stack(s, RX + 14, y0 + 58, RW - 28, [
        ("ServiceConnection", "cpp", "qml/ServiceConnection.h/.cpp", [
            "the Cap'n Proto client in its own thread (KJ);",
            "reconnects every second, commands are queued"]),
        ("WindowSource", "cpp", "qml/WindowSource.h/.cpp, WindowInfo.h", [
            "the window list of the process (GUI thread), shared",
            "by every model; kept while the service restarts"]),
        ("TasksModel", "qml", "qml/TasksModel.h/.cpp, AbstractTasksModel.h", [
            "the API of Plasma's TasksModel (org.kde.taskmanager):",
            "roles display, decoration, AppName, IsActive ...;",
            "requestActivate, requestClose, requestToggleMinimized ..."]),
    ])
    lib.h = frame_height(y0, lb)
    s.library(lib, "Maia.Windows", "QML module (C++)", "Maia/services/windows/qml/  ->  <qml dir>/Maia/Windows")
    cy = lib.bottom + 40
    client = Rect(RX, cy, RW, 0)
    shells, cb = stack(s, RX + 14, cy + 52, RW - 28, [
        ("Lumen taskbar", "shell", "frontends/Lumen/shell/windows/TaskbarWindow.qml", []),
        ("XPLuna taskbar", "shell", "frontends/XPLuna/shell/taskbar/TaskbarContent.qml", []),
        ("Ubuntu 24.04 dock", "shell", "frontends/Ubuntu 24.04/shell/dock/SidePanelContent.qml", []),
        ("Maia dock", "shell", "frontends/Maia/shell/dock/Dock.qml", []),
    ])
    client.h = frame_height(cy, cb)
    s.process(client, "appMaiaServer", "the shell of the active frontend", PROCESS_CLIENT)

    # --- Connections ---
    s.link(proto, kwinrs, "wayland", LANE_L[0], both=True, label="Wayland")
    s.link(icons, kwinrs, "wayland", LANE_L[1], b_dy=14, label="icon pipe")
    s.link(entries, apps, "file", LANE_L[2], label="reads")
    s.link(proc, apps, "file", LANE_L[3], b_dy=14, label="reads")
    s.link(launch, started, "spawn", LANE_L[4], label="starts")
    s.link(kwinrs, model, "call", LANE_M[0], a_dy=-10, label="events")
    s.link(apps, model, "call", LANE_M[1], b_dy=12)
    s.link(rpc, kwinrs, "call", LANE_M[2], b_dy=14, label="Command")
    s.link(rpc, launch, "call", LANE_M[3], a_dy=12, label="launch")
    s.down(model, throttle, "call")
    s.down(throttle, rpc, "call")
    s.link(rpc, conn, "capnp", LANE_R[1], both=True, label="Cap'n Proto\nsocket")
    s.down(conn, source, "call")
    s.down(source, tasks, "call")
    s.arrow([(tasks.mid_x(), lib.bottom), (tasks.mid_x(), client.y)], "import", label="import Maia.Windows",
            label_at=(tasks.mid_x() + 8, lib.bottom + 24))

    y = max(contract.bottom, started.bottom, client.bottom)
    api = [
        [("WindowService", "the service", [
            ("info() -> (backend, capabilities, version)", ""),
            ("watch(listener) -> subscription", "a snapshot, then changes"),
            ("control() -> WindowControl", ""),
            ("icon(id) -> (data, serial)", "the window's bitmap icon"),
          ]),
         ("WindowListener", "implemented by the client", [
            ("snapshot(windows)", "every window, first"),
            ("added(window) · changed(window)", "the whole window again"),
            ("removed(id)", ""),
          ])],
        [("WindowControl", "the service", [
            ("activate(id) · close(id)", ""),
            ("setMinimized(id, on) · setMaximized(id, on)", ""),
            ("setFullscreen(id, on)", ""),
            ("setKeepAbove(id, on) · setKeepBelow(id, on)", ""),
            ("requestMove(id) · requestResize(id)", "interactive, done by KWin"),
            ("launchNewInstance(id)", "starts the window's app again"),
            ("launch(launcherUrl)", "applications:<desktop entry id>"),
          ])],
        [("Window", "a value", [
            ("id · title · appId · rawAppId", ""),
            ("appName · genericName · iconName", "from the desktop entry"),
            ("iconSerial · launcherUrl · pid", ""),
            ("states", "active, minimized, maximized, ... (bits)"),
            ("geometry · virtualDesktops · parentId", ""),
            ("lastActivated · canLaunchNewInstance", ""),
          ]),
         ("TasksModel (QML)", "Maia.Windows", [
            ("requestActivate(index) · requestClose(index)", ""),
            ("requestToggleMinimized / Maximized (index)", ""),
            ("launch(launcherUrl)", ""),
          ])],
    ]
    repo = [
        ("Maia/services/windows/contract/windows.capnp", "the contract (read it first)"),
        ("Maia/services/windows/service/", "the service, Rust crate maia-windows-service (tests/service.rs: over a real connection)"),
        ("Maia/services/windows/qml/", "Maia.Windows, the QML module (tests/tst_tasksmodel.cpp)"),
        ("Maia/services/windows/README.md", "overview, running by hand, testing"),
        ("Maia/DeployFiles/session/", "the session scripts start the service (KWin and Wayfire)"),
        ("cmake/MaiaRust.cmake, MaiaCapnProto.cmake, MaiaQmlModule.cmake", "builds cargo, the contract and the QML module"),
        ("3rdparty/capnproto/", "Cap'n Proto for C++ (bundled)"),
    ]
    finish(s, y, api, repo, "maia-windows-service.svg")


# ---------------------------------------------------------------------------------------------
# maia-network-service
# ---------------------------------------------------------------------------------------------

def network():
    s = Svg(W)
    header(s, "maia-network-service: Wi-Fi for a Maia session",
           "The only Maia process that talks to NetworkManager: the state of Wi-Fi for shells and Maia Settings, their commands, "
           "and the session's password dialog (secret agent). Repository: Maia/services/network/")
    y0 = TOP + 50

    # --- Left ---
    nm = Rect(LX, y0, LW, 0)
    (nmapi, nmsettings_api, agentmgr), b = stack(s, LX + 14, y0 + 52, LW - 28, [
        ("Devices and networks", "system", "org.freedesktop.NetworkManager", [
            "Device, Device.Wireless, AccessPoint, ActiveConnection,",
            "IP4Config, IP6Config: properties and their signals"]),
        ("Saved profiles", "system", ".../Settings, Settings.Connection", [
            "GetSettings, Update, GetSecrets, Delete;",
            "AddAndActivateConnection, ActivateConnection"]),
        ("Secret agents", "system", ".../AgentManager", [
            "asks the registered agent for passwords (GetSecrets)"]),
    ])
    nm.h = frame_height(y0, b)
    s.process(nm, "NetworkManager", "system service (root)", PROCESS_SYSTEM)
    y = nm.bottom + 20
    bus = s.bus(LX, y, LW, "System D-Bus", ["every call and signal above goes over it"])
    y = bus.bottom + 20
    polkit = Rect(LX, y, LW, 0)
    (pk,), b = stack(s, LX + 14, y + 52, LW - 28, [
        ("Authorization", "system", "org.freedesktop.PolicyKit1", [
            "NetworkManager asks it before a change (Wi-Fi on/off,",
            "system profiles); it may ask the user (interactive)"]),
    ])
    polkit.h = frame_height(y, b)
    s.process(polkit, "polkit", "system service", PROCESS_SYSTEM)
    y = polkit.bottom + 20
    hostname = s.file(LX, y, LW, "/proc/sys/kernel/hostname", ["the hotspot's network name when none is given"])
    y = hostname.bottom + 16
    kded = s.file(LX, y, LW, "kded6rc (Maia's defaults)", [
        "turns KDE's networkmanagement agent off in a Maia",
        "session: one secret agent per session"], ["<prefix>/etc/xdg/kded6rc"])

    # --- Middle ---
    svc = Rect(MX, y0, MW, 0)
    (nmrs, nmsettings, nmdefs, agent, settings, fake), a_b = stack(s, AX, y0 + 72, AW, [
        ("nm.rs", "rust", "service/src/nm.rs", [
            "NetworkManager backend (zbus): signals mark",
            "objects dirty, re-read 30 ms later; commands",
            "as D-Bus calls (interactive polkit)"]),
        ("nmsettings.rs", "rust", "service/src/nmsettings.rs", [
            "profiles (a{sa{sv}}) <-> settings, secrets;",
            "edits keep unknown keys; hotspot, hidden",
            "and Enterprise profiles"]),
        ("nmdefs.rs", "rust", "service/src/nmdefs.rs", ["NetworkManager's numbers: states, reasons, flags"]),
        ("agent.rs", "rust", "service/src/agent.rs", [
            "the secret agent: a D-Bus object",
            "(...NetworkManager.SecretAgent),",
            "registered as org.maia.network"]),
        ("settings.rs", "rust", "service/src/settings.rs", [
            "connection settings, secrets, the rules of",
            "passwords (8-63 characters, WEP keys)"]),
        ("fake.rs", "rust", "service/src/fake.rs", [
            "a simulated NetworkManager for tests",
            "(MAIA_NETWORK_BACKEND=fake)"]),
    ])
    (backend, model, throttle, qr, prompt, rpc, main), b_b = stack(s, BX, y0 + 72, BW, [
        ("backend.rs", "rust", "service/src/backend.rs", ["BackendEvent, Command, Reply: backend <-> hub"]),
        ("model.rs", "rust", "service/src/model.rs", [
            "access points -> networks (GNOME's order),",
            "saved connections (pure logic)"]),
        ("throttle.rs", "rust", "service/src/throttle.rs", ["at most one change per object every 250 ms"]),
        ("qr.rs", "rust", "service/src/qr.rs", ["the Wi-Fi QR text and matrix (qrcodegen)"]),
        ("prompt.rs", "rust", "service/src/prompt.rs", ["password requests: agent -> the shell"]),
        ("rpc.rs", "rust", "service/src/rpc.rs", [
            "the hub: snapshot + changes to listeners,",
            "NetworkControl, the shell's SecretPrompter"]),
        ("main.rs", "rust", "service/src/main.rs", [
            "socket .../maia/network-$WAYLAND_DISPLAY.sock;",
            "backend: networkmanager | fake"]),
    ])
    svc.h = frame_height(y0, a_b, b_b)
    s.process(svc, "maia-network-service", "Maia service (Rust)", PROCESS_MAIA,
              "Maia/services/network/service/   ->   <prefix>/libexec/maia-network-service")
    contract = s.card(MX, svc.bottom + 20, MW, "network.capnp", "contract", [
        "NetworkService, NetworkListener, NetworkControl, SecretPrompter; Status, WifiDevice, WifiNetwork,",
        "SavedConnection, ConnectionSettings, Secret, SecretRequest"], "Maia/services/network/contract/network.capnp")

    # --- Right ---
    lib = Rect(RX, y0, RW, 0)
    (conn, source, status, models, secretprompt, control), lb = stack(s, RX + 14, y0 + 58, RW - 28, [
        ("NetworkConnection", "cpp", "qml/NetworkConnection.h/.cpp", [
            "the Cap'n Proto client (KJ thread); renews the",
            "prompter registration after a reconnection"]),
        ("NetworkSource", "cpp", "qml/NetworkSource.h/.cpp, NetworkTypes.h", [
            "the network state of the process (GUI thread);",
            "abstract: the tests fill their own"]),
        ("WifiStatus, WifiDevicesModel", "qml", "qml/WifiStatus.*, WifiDevicesModel.*", [
            "the state at a glance (toggle, icon, captive portal);",
            "the adapters, their addresses and speed"]),
        ("WifiNetworksModel, SavedNetworksModel", "qml", "qml/WifiNetworksModel.*, SavedNetworksModel.*", [
            "networks in reach (GNOME's order), saved profiles;",
            "connectNetwork, activate, forget"]),
        ("SecretPrompt", "qml", "qml/SecretPrompt.*", [
            "the password dialog of the session: the shell",
            "answers NetworkManager's requests"]),
        ("NetworkControl, QrCodeView, Network", "qml", "qml/NetworkControl.*, SettingsMap.*, QrCodeView.*", [
            "settings and secrets as JavaScript objects, hidden",
            "and Enterprise networks, hotspot; the QR code; enums"]),
    ])
    lib.h = frame_height(y0, lb)
    s.library(lib, "Maia.Network", "QML module (C++)", "Maia/services/network/qml/  ->  <qml dir>/Maia/Network")
    cy = lib.bottom + 40
    shell = Rect(RX, cy, RW, 0)
    (wifipage, shellstate), sb = stack(s, RX + 14, cy + 52, RW - 28, [
        ("Quick settings: Wi-Fi", "shell", "frontends/Lumen/shell/windows/QuickSettingsWifiPage.qml", [
            "networks, inline password, captive portal"]),
        ("Shell state, password prompt", "shell", "frontends/Lumen/shell/state/Shell.qml", [
            "WifiStatus for the tray icon; SecretPrompt"]),
    ])
    shell.h = frame_height(cy, sb)
    s.process(shell, "appMaiaServer (Lumen)", "the shell", PROCESS_CLIENT)
    cy = shell.bottom + 20
    settingsapp = Rect(RX, cy, RW, 0)
    (page,), sb = stack(s, RX + 14, cy + 52, RW - 28, [
        ("Wi-Fi page", "shell", "apps/settings/pages/network/", [
            "networks, saved, hidden, hotspot, QR code, the",
            "details editor (IPv4/IPv6, security, 802.1X)"]),
    ])
    settingsapp.h = frame_height(cy, sb)
    s.process(settingsapp, "maia-settings", "Maia Settings (app)", PROCESS_CLIENT)

    # --- Connections ---
    s.link(nmapi, nmrs, "dbus", LANE_L[0], both=True, label="D-Bus: calls,\nsignals")
    s.link(nmsettings_api, nmrs, "dbus", LANE_L[1], b_dy=14, label="D-Bus")
    s.link(agentmgr, agent, "dbus", LANE_L[2], both=True, label="GetSecrets")
    s.link(hostname, nmrs, "file", LANE_L[4], b_dy=24, label="reads")
    s.arrow([(nm.mid_x(), nm.bottom), (nm.mid_x(), bus.y)], "dbus")
    s.arrow([(nm.mid_x(), bus.bottom), (nm.mid_x(), polkit.y)], "dbus", label="CheckAuthorization",
            label_at=(nm.mid_x() + 8, bus.bottom + 14))
    s.down(nmrs, nmsettings, "call")
    s.link(nmrs, backend, "call", LANE_M[0], label="events")
    s.link(rpc, nmrs, "call", LANE_M[1], b_dy=14, label="Command")
    s.link(agent, prompt, "call", LANE_M[2], label="request")
    s.down(prompt, rpc, "call")
    s.link(rpc, conn, "capnp", LANE_R[1], both=True, label="Cap'n Proto\nsocket")
    s.link(rpc, secretprompt, "capnp", LANE_R[3], a_dy=14, label="ask(),\ncancel()", label_dy=26)
    s.down(conn, source, "call")
    s.down(source, status, "call")
    s.arrow([(status.mid_x(), lib.bottom), (status.mid_x(), shell.y)], "import", label="import Maia.Network",
            label_at=(status.mid_x() + 8, lib.bottom + 24))

    y = max(contract.bottom, kded.bottom, settingsapp.bottom)
    api = [
        [("NetworkService", "the service", [
            ("info() -> (backend, version)", ""),
            ("watch(listener) -> subscription", "a snapshot, then changes"),
            ("control() -> NetworkControl", ""),
            ("registerPrompter(prompter) -> registration", "the shell"),
          ]),
         ("NetworkListener", "implemented by the client", [
            ("snapshot(snapshot) · statusChanged(status)", ""),
            ("deviceChanged / deviceRemoved", ""),
            ("networkChanged / networkRemoved", ""),
            ("connectionChanged / connectionRemoved", ""),
            ("event(activationFailed | connected)", ""),
          ])],
        [("NetworkControl", "the service", [
            ("setWirelessEnabled(enabled)", ""),
            ("requestScan(deviceId)", ""),
            ("connect(networkId)", "saved or new; password via the prompter"),
            ("activate(uuid, deviceId)", ""),
            ("connectWithSettings(device, settings, secrets)", "hidden, Enterprise"),
            ("disconnect(deviceId) · forget(uuid)", ""),
            ("checkConnectivity()", "after a captive portal"),
          ])],
        [("NetworkControl (continued)", "", [
            ("settings(uuid) -> settings", "the details editor"),
            ("updateSettings(uuid, settings, secrets)", ""),
            ("secrets(uuid) -> secrets", "may ask polkit"),
            ("qrCode(uuid) -> (text, size, modules)", ""),
            ("startHotspot(device, ssid, kind, password)", "-> (uuid, password)"),
            ("stopHotspot(deviceId)", ""),
          ]),
         ("SecretPrompter", "implemented by the shell", [
            ("ask(request) -> reply", "cancelled, or the secrets"),
            ("cancel(id)", "NetworkManager gave up"),
          ])],
    ]
    repo = [
        ("Maia/services/network/contract/network.capnp", "the contract (read it first)"),
        ("Maia/services/network/service/", "the service, Rust crate maia-network-service (tests/, examples/watch.rs, profiles.rs)"),
        ("Maia/services/network/qml/", "Maia.Network, the QML module (tests/tst_networkmodels.cpp)"),
        ("Maia/services/network/docs/gnome-wifi-features.md", "what the interface offers (from GNOME), now and later"),
        ("apps/settings/pages/network/", "the Wi-Fi page of Maia Settings"),
        ("Maia/frontends/Lumen/shell/windows/QuickSettingsWifiPage.qml", "Lumen's quick settings"),
        ("Maia/DeployFiles/etc/xdg/kded6rc", "KDE's secret agent off in Maia sessions"),
    ]
    finish(s, y, api, repo, "maia-network-service.svg")


# ---------------------------------------------------------------------------------------------
# maia-appearance-service
# ---------------------------------------------------------------------------------------------

def appearance():
    s = Svg(W)
    header(s, "maia-appearance-service: how a Maia session looks",
           "The one place that knows how the compositor stores its look: window decorations now (choose, install, one per frontend); "
           "icons, cursors and colors later. Repository: Maia/services/appearance/")
    y0 = TOP + 50

    # --- Left ---
    kwin = Rect(LX, y0, LW, 0)
    (kdbus, bridge), b = stack(s, LX + 14, y0 + 52, LW - 28, [
        ("KWin's D-Bus", "system", "/KWin  org.kde.KWin", [
            "reloadConfig (signal): KWin re-reads kwinrc",
            "supportInformation(): what it really loaded"]),
        ("Decoration bridge", "system", "kwin/src/decorations/decorationbridge.cpp", [
            "loads the decoration plugin and theme kwinrc names",
            "(Breeze, Aurorae v2 ...), falls back to Breeze"]),
    ])
    kwin.h = frame_height(y0, b)
    s.process(kwin, "kwin_wayland", "the compositor (system)", PROCESS_SYSTEM)
    y = kwin.bottom + 26
    kwinrc = s.file(LX, y, LW, "kwinrc", ["library, theme, BorderSize, BorderSizeAuto"],
                    ["$XDG_CONFIG_HOME/kwinrc  [org.kde.kdecoration2]"])
    y = kwinrc.bottom + 26
    kwrite = Rect(LX, y, LW, 84)
    s.process(kwrite, "kwriteconfig6", "child process (KDE tool)", PROCESS_CHILD)
    s.text(LX + 16, y + 62, "writes kwinrc with KConfig's locking and escaping", size=12, fill="#334155")
    y = kwrite.bottom + 22
    themes = s.file(LX, y, LW, "Theme directories", [
        "the user's first, then Maia's <prefix>/share, then the",
        "system's; watched (inotify) for themes added elsewhere"],
        ["<data dir>/aurorae/themes/<name>/", "<data dir>/kwin/decorations/<id>/", "<qt plugins>/org.kde.kdecoration3/*.so"])
    y = themes.bottom + 22
    tar = Rect(LX, y, LW, 84)
    s.process(tar, "tar, unzip", "child processes", PROCESS_CHILD)
    s.text(LX + 16, y + 62, "unpack theme archives into a private staging directory", size=12, fill="#334155")
    y = tar.bottom + 22
    choices = s.file(LX, y, LW, "appearance.json", ["the decoration remembered for each frontend"],
                     ["$XDG_CONFIG_HOME/maia/<version>/appearance.json"])

    # --- Middle ---
    svc = Rect(MX, y0, MW, 0)
    (kwinrs, comp, catalog, qtplugin, install, frontends), a_b = stack(s, AX, y0 + 72, AW, [
        ("compositor/kwin.rs", "rust", "service/src/compositor/kwin.rs", [
            "theme ids <-> kwinrc; writes with kwriteconfig6,",
            "reloadConfig, waits for supportInformation;",
            "watches kwinrc"]),
        ("compositor/mod.rs, fake.rs", "rust", "service/src/compositor/", [
            "the Compositor trait: info, read, apply_theme,",
            "apply_border_size, watch; fake: in memory"]),
        ("decorations/catalog.rs", "rust", "service/src/decorations/catalog.rs", [
            "finds the themes of every engine on disk"]),
        ("decorations/qtplugin.rs", "rust", "service/src/decorations/qtplugin.rs", [
            "plugin names from the ELF note",
            ".note.qt.metadata (CBOR), without Qt"]),
        ("decorations/install.rs", "rust", "service/src/decorations/install.rs", [
            "install from a directory or an archive (listing",
            "and tree checked, one rename); remove"]),
        ("decorations/frontends.rs", "rust", "service/src/decorations/frontends.rs", [
            "the choice per frontend (appearance.json)"]),
    ])
    (area, theme, rpcdec, rpcmod, shared, main), b_b = stack(s, BX, y0 + 72, BW, [
        ("decorations/mod.rs", "rust", "service/src/decorations/mod.rs", [
            "the area: one change at a time, events to",
            "subscribers, frontend activations"]),
        ("decorations/theme.rs", "rust", "service/src/decorations/theme.rs", [
            "Engine, ThemeId \"engine:name\", Theme,",
            "Current, BorderSize"]),
        ("rpc/decorations.rs", "rust", "service/src/rpc/decorations.rs", [
            "the Decorations interface, its listeners,",
            "FrontendActivation capabilities"]),
        ("rpc/mod.rs", "rust", "service/src/rpc/mod.rs", ["AppearanceService, serve(), results"]),
        ("paths, kconfig, inotify, error", "rust", "service/src/*.rs", [
            "XDG directories and origins, reading KConfig",
            "files, watching directories, ErrorCode"]),
        ("main.rs", "rust", "service/src/main.rs", [
            "socket .../maia/appearance-$WAYLAND_DISPLAY.sock;",
            "backend: kwin | fake"]),
    ])
    svc.h = frame_height(y0, a_b, b_b)
    s.process(svc, "maia-appearance-service", "Maia service (Rust)", PROCESS_MAIA,
              "Maia/services/appearance/service/   ->   <prefix>/libexec/maia-appearance-service")
    contract = s.card(MX, svc.bottom + 20, MW, "common, decorations, appearance .capnp", "contract", [
        "one file per area: a new area (icons, cursors) is a new file and a method of AppearanceService;",
        "themes are named \"<engine>:<name>\" on every compositor (aurorae-svg:XBoomer, kdecoration:org.kde.breeze)"],
        "Maia/services/appearance/contract/")
    guide = s.card(MX, contract.bottom + 14, MW, "Extending it", "config", [
        "docs/adding-an-area.md (icons, cursors, colors)  -  docs/adding-a-compositor.md (Wayfire)"],
        "Maia/services/appearance/docs/")

    # --- Right ---
    lib = Rect(RX, y0, RW, 0)
    (conn, source, decorations, look), lb = stack(s, RX + 14, y0 + 58, RW - 28, [
        ("AppearanceConnection", "cpp", "qml/AppearanceConnection.h/.cpp", [
            "the Cap'n Proto client (KJ thread); renews the",
            "frontend activations after a reconnection"]),
        ("AppearanceSource", "cpp", "qml/AppearanceSource.h/.cpp, AppearanceTypes.h", [
            "the appearance state of the process (GUI thread)"]),
        ("WindowDecorations", "qml", "qml/WindowDecorations.h/.cpp", [
            "the themes as a list model; setTheme, setBorderSize,",
            "install, remove; compositor, capabilities"]),
        ("FrontendLook, Appearance", "qml", "qml/FrontendLook.h/.cpp", [
            "a frontend's default look; it holds the frontend's",
            "activation while it exists; the enums"]),
    ])
    lib.h = frame_height(y0, lb)
    s.library(lib, "Maia.Appearance", "QML module (C++)", "Maia/services/appearance/qml/  ->  <qml dir>/Maia/Appearance")
    cy = lib.bottom + 40
    shell = Rect(RX, cy, RW, 0)
    shells, sb = stack(s, RX + 14, cy + 52, RW - 28, [
        ("Lumen", "shell", "frontends/Lumen/shell/Main.qml", ["FrontendLook: aurorae-svg:Se7enAero"]),
        ("XPLuna", "shell", "frontends/XPLuna/shell/Main.qml", ["FrontendLook: aurorae-svg:XBoomer"]),
        ("Ubuntu 24.04", "shell", "frontends/Ubuntu 24.04/shell/Main.qml", ["FrontendLook: kdecoration:org.kde.breeze"]),
        ("Maia", "shell", "frontends/Maia/shell/Main.qml", ["FrontendLook: kdecoration:org.kde.oxygen"]),
    ])
    shell.h = frame_height(cy, sb)
    s.process(shell, "appMaiaServer", "the shell of the active frontend", PROCESS_CLIENT)
    s.text(RX, shell.bottom + 24, "Later: a window decorations page in Maia Settings (WindowDecorations)", size=12,
           fill="#475569", italic=True)

    # --- Connections ---
    s.link(kdbus, kwinrs, "dbus", LANE_L[0], both=True, label="D-Bus")
    s.arrow([(kwin.mid_x(), kwinrc.y), (kwin.mid_x(), kwin.bottom)], "file", label="reads",
            label_at=(kwin.mid_x() + 8, kwin.bottom + 17))
    s.arrow([(kwinrc.mid_x(), kwrite.y), (kwinrc.mid_x(), kwinrc.bottom)], "file", label="writes",
            label_at=(kwinrc.mid_x() + 8, kwinrc.bottom + 17))
    s.link(kwinrs, kwinrc, "file", LANE_L[1], a_dy=10, label="reads, watches")
    s.link(kwinrs, kwrite, "spawn", LANE_L[2], a_dy=24, label="runs")
    s.link(catalog, themes, "file", LANE_L[3], b_dy=-20, label="lists")
    s.link(qtplugin, themes, "file", LANE_L[4], b_dy=0, label="reads .so")
    s.link(install, themes, "file", LANE_L[1], a_dy=-8, b_dy=20, label="installs")
    s.link(install, tar, "spawn", LANE_L[2], a_dy=10, label="runs")
    s.link(frontends, choices, "file", LANE_L[3], label="reads, writes")
    s.link(area, comp, "call", LANE_M[0])
    s.link(area, catalog, "call", LANE_M[1], a_dy=10)
    s.link(area, install, "call", LANE_M[2], a_dy=18)
    s.link(area, frontends, "call", LANE_M[3], a_dy=26)
    s.arrow([(comp.mid_x(), comp.y), (comp.mid_x(), kwinrs.bottom)], "call")
    s.arrow([(area.mid_x() + 60, rpcdec.y), (area.mid_x() + 60, theme.bottom)], "call")
    s.link(rpcdec, conn, "capnp", LANE_R[1], both=True, label="Cap'n Proto\nsocket")
    s.down(conn, source, "call")
    s.down(source, decorations, "call")
    s.arrow([(look.mid_x(), lib.bottom), (look.mid_x(), shell.y)], "import", label="import Maia.Appearance",
            label_at=(look.mid_x() + 8, lib.bottom + 24))

    y = max(guide.bottom, choices.bottom, shell.bottom + 30)
    api = [
        [("AppearanceService", "the service", [
            ("info() -> (backend, compositor, version)", ""),
            ("decorations() -> Decorations", "one interface per area"),
          ]),
         ("DecorationsListener", "implemented by the client", [
            ("snapshot(themes, current)", "first"),
            ("themesChanged(themes)", "installed, removed"),
            ("currentChanged(current)", "the choice, the frontend"),
          ])],
        [("Decorations", "the service", [
            ("capabilities() -> (compositor, engines, ...)", ""),
            ("list() -> themes · current() -> current", ""),
            ("watch(listener) -> subscription", ""),
            ("set(themeId) -> result", "once the compositor took it"),
            ("setBorderSize(size) -> result", ""),
          ])],
        [("Decorations (continued)", "", [
            ("install(path) -> (result, themeId)", "dir or archive, checked"),
            ("remove(themeId) -> result", "the user's themes only"),
            ("activateFrontend(frontend, default)", "-> (result, activation)"),
            ("refresh()", "looks for themes again"),
          ]),
         ("Theme", "a value", [
            ("id · engine · name · description · author", ""),
            ("origin", "system, maia, user"),
            ("available · unavailableReason · path", ""),
          ])],
    ]
    repo = [
        ("Maia/services/appearance/contract/", "the contract: common, decorations, appearance .capnp"),
        ("Maia/services/appearance/service/", "the service, Rust crate maia-appearance-service (src/lib.rs: map of the code)"),
        ("Maia/services/appearance/qml/", "Maia.Appearance, the QML module (tests/tst_appearance.cpp)"),
        ("Maia/services/appearance/docs/", "maia-appearance-service.svg (this diagram), adding-an-area.md, adding-a-compositor.md"),
        ("Maia/frontends/*/assets/decorations/", "themes the frontends ship (installed to <prefix>/share/aurorae/themes)"),
        ("Maia/frontends/*/shell/Main.qml", "FrontendLook: each frontend's default decoration"),
        ("Maia/DeployFiles/session/", "starts the service (KWin session); Maia's share is in XDG_DATA_DIRS"),
    ]
    finish(s, y, api, repo, "maia-appearance-service.svg")


if __name__ == "__main__":
    windows()
    network()
    appearance()
