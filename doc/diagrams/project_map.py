#!/usr/bin/env python3
"""The map of the whole Maia Shell project, one SVG.

    python3 <path>/project_map.py              (from any directory)

writes maia-project-map.svg into the current directory. The map, from the top:

    1. the start of a session: from the session file of SDDM to the shell, who starts whom
    2. the running session, in three columns, one row per subject (windows, appearance, network,
       the server, the rest), so that most connections run straight from left to right:
           Linux (kernel, system daemons)  |  Maia (services, QML modules)  |  frontends and apps
       the Wayland display is the road at the top every window connects to
    3. where things are: the repository, the installation, the user's files

What the services offer is told by their contracts (Cap'n Proto, D-Bus), not by their insides:
the diagrams of the single services (service_diagrams.py) show those. Change the descriptions
here when the project changes; svgkit.py draws the shapes.
"""

import os
import sys
import textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import svgkit  # noqa: E402
from svgkit import PROCESS_CHILD, PROCESS_CLIENT, PROCESS_MAIA, PROCESS_SYSTEM, Rect, Svg  # noqa: E402

# --- The visual language of the map: svgkit's, with what a whole session adds ---

svgkit.KIND.update({
    "capnp": ("Cap'n Proto contract", "#7c3aed"),
    "dbus": ("D-Bus contract", "#2563eb"),
    "dbusapi": ("D-Bus service", "#2563eb"),
    "kernel": ("kernel", "#334155"),
    "tool": ("tool", "#64748b"),
    "qmlfile": ("QML files", "#0369a1"),
})
svgkit.ARROW.clear()
svgkit.ARROW.update({
    "wayland": ("#16a34a", False, "Wayland protocol (the display socket)"),
    "capnp": ("#7c3aed", False, "Cap'n Proto RPC over a Unix socket"),
    "dbus": ("#2563eb", False, "D-Bus, session bus"),
    "dbussys": ("#1e3a8a", False, "D-Bus, system bus"),
    "pulse": ("#db2777", False, "PulseAudio protocol (PipeWire)"),
    "socket": ("#0891b2", False, "other socket (QLocalSocket, WebSocket)"),
    "kernel": ("#475569", False, "device files, system calls"),
    "file": ("#ea580c", False, "reads / writes a file"),
    "spawn": ("#64748b", True, "starts a process"),
    "import": ("#0284c7", True, "QML import (module loaded into the process)"),
})

KERNEL = "#334155"
W = 3640

# Columns of the running session (x, width)
KX, KW = 40, 250            # Linux kernel
LX, LW = 330, 640           # system daemons
SX, SW = 1110, 580          # Maia services and the server
QX, QW = 1790, 480          # Maia's QML modules
EX, EW = 2370, 600          # the QML engine of the server (the shell)
RX, RW = 3050, 550          # apps, client processes, frontend directories

PAD = 14                    # inside a process frame
GAP = 10                    # between the cards of a frame
BLOCK_GAP = 18              # between the blocks of a column

TEXT_CH = 5.85              # average width of a character of 11.5 px text
MONO_CH = 6.4               # of 10.5 px monospace text


def wrap(lines, width, mono=False):
    """Lines that fit into width (pixels); a wrapped line continues indented"""
    chars = max(10, int(width / (MONO_CH if mono else TEXT_CH)))
    out = []
    for line in lines:
        out.extend(textwrap.wrap(line, chars, subsequent_indent="   ", break_long_words=False,
                                 break_on_hyphens=False) or [""])
    return out


# --- Elements: measured first (the rows take the height of their tallest column), drawn after ---

class Card:
    """A module, class or component inside a frame; kind picks its tag"""

    def __init__(self, title, kind, lines=(), path=None, name=None):
        self.title, self.kind, self.lines, self.path, self.name = title, kind, list(lines), path, name

    def _lines(self, w):
        return wrap(self.lines, w - 28)

    def _paths(self, w):
        return wrap([self.path], w - 28, mono=True) if self.path else []

    def height(self, w):
        return 30 + 16 * len(self._paths(w)) + 15 * len(self._lines(w)) + 8

    def draw(self, s, x, y, w):
        label, color = svgkit.KIND[self.kind]
        h = self.height(w)
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#ffffff" stroke="#94a3b8" stroke-width="1.5"/>')
        s.add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
        s.text(x + 14, y + 21, self.title, size=13.5, weight="bold")
        s.tag(x + w - 8, y + 7, label, color)
        cy = y + 38
        for p in self._paths(w):
            s.text(x + 14, cy, p, size=10.5, fill="#64748b", mono=True)
            cy += 16
        for line in self._lines(w):
            s.text(x + 14, cy, line, size=11.5, fill="#334155")
            cy += 15
        return Rect(x, y, w, h)


class Contract:
    """The API of a contract: its interfaces and their methods, with what each one does"""

    def __init__(self, title, kind, path, interfaces, name=None):
        self.title, self.kind, self.path, self.interfaces, self.name = title, kind, path, interfaces, name

    def _layout(self, w):
        """[(kind, text, x offset)] one entry per line"""
        rows = []
        for iface, who, methods in self.interfaces:
            rows.append(("iface", iface, who))
            for signature, note in methods:
                sig_w = 6.6 * len(signature)
                if not note:
                    rows.append(("sig", signature, None))
                elif 22 + sig_w + 12 + TEXT_CH * len(note) <= w - 14:
                    rows.append(("sig", signature, note))
                else:
                    rows.append(("sig", signature, None))
                    for part in wrap([note], w - 50):
                        rows.append(("note", part, None))
        return rows

    def height(self, w):
        rows = self._layout(w)
        path_h = 16 * len(wrap([self.path], w - 28, mono=True)) if self.path else 0
        h = 32 + path_h
        for kind, _, _ in rows:
            h += 19 if kind == "iface" else 15
        return h + 8

    def draw(self, s, x, y, w):
        label, color = svgkit.KIND[self.kind]
        h = self.height(w)
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#faf5ff" stroke="{color}" stroke-width="1.6"/>')
        s.add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
        s.text(x + 14, y + 21, self.title, size=13.5, weight="bold", fill="#3b0764" if self.kind == "capnp" else "#172554")
        s.tag(x + w - 8, y + 7, label, color)
        cy = y + 38
        if self.path:
            for p in wrap([self.path], w - 28, mono=True):
                s.text(x + 14, cy, p, size=10.5, fill="#64748b", mono=True)
                cy += 16
        for kind, text, extra in self._layout(w):
            if kind == "iface":
                cy += 4
                s.text(x + 14, cy, text, size=12.5, weight="bold", fill=color)
                if extra:
                    s.text(x + 14 + 7.6 * len(text) + 10, cy, extra, size=11, fill="#64748b", italic=True)
                cy += 15
            elif kind == "sig":
                s.text(x + 22, cy, text, size=11, fill="#0f172a", mono=True)
                if extra:
                    s.text(x + 22 + 6.6 * len(text) + 12, cy, extra, size=11.5, fill="#475569")
                cy += 15
            else:
                s.text(x + 36, cy, text, size=11.5, fill="#475569")
                cy += 15
        return Rect(x, y, w, h)


class Socket:
    """A Unix socket a process listens on"""

    def __init__(self, title, color="#7c3aed", name=None):
        self.title, self.color, self.name = title, color, name

    def height(self, w):
        return 26

    def draw(self, s, x, y, w):
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="26" rx="13" fill="{self.color}" fill-opacity="0.08" '
              f'stroke="{self.color}" stroke-width="1.8"/>')
        s.text(x + 14, y + 17, "socket", size=11, weight="bold", fill=self.color)
        s.text(x + 66, y + 17, self.title, size=10.5, fill="#1e293b", mono=True)
        return Rect(x, y, w, 26)


class Process:
    """A process (thick frame) or a library loaded into processes (dashed frame) with its cards"""

    def __init__(self, title, subtitle, color, path=None, children=(), name=None, library=False, note=None):
        self.title, self.subtitle, self.color, self.path = title, subtitle, color, path
        self.children, self.name, self.library, self.note = list(children), name, library, note

    def _paths(self, w):
        return wrap([self.path], w - 32, mono=True) if self.path else []

    def _notes(self, w):
        return wrap([self.note], w - 32) if self.note else []

    def head(self, w):
        top = 44 if self.library else 50
        return top + 16 * len(self._paths(w)) + 15 * len(self._notes(w)) + 6

    def height(self, w):
        h = self.head(w)
        for c in self.children:
            h += c.height(w - 2 * PAD) + GAP
        return h + PAD - (GAP if self.children else 0) + (0 if self.children else 4)

    def draw_frame(self, s, x, y, w, h):
        r = Rect(x, y, w, h)
        if self.library:
            s.library(r, self.title, self.subtitle, color=self.color)
            cy = y + 44
        else:
            s.process(r, self.title, self.subtitle, self.color)
            cy = y + 58
        for p in self._paths(w):
            s.text(x + 16, cy, p, size=10.5, fill="#334155", mono=True)
            cy += 16
        for n in self._notes(w):
            s.text(x + 16, cy, n, size=11.5, fill="#334155", italic=True)
            cy += 15
        return r

    def draw(self, s, x, y, w, registry=None):
        h = self.height(w)
        r = self.draw_frame(s, x, y, w, h)
        cy = y + self.head(w)
        for c in self.children:
            cr = c.draw(s, x + PAD, cy, w - 2 * PAD)
            if registry is not None and c.name:
                registry[c.name] = cr
            cy += c.height(w - 2 * PAD) + GAP
        return r


class File:
    """A file or directory on disk"""

    def __init__(self, title, paths=(), lines=(), name=None):
        self.title, self.paths, self.lines, self.name = title, list(paths), list(lines), name

    def _paths(self, w):
        return wrap(self.paths, w - 30, mono=True)

    def _lines(self, w):
        return wrap(self.lines, w - 30)

    def height(self, w):
        return 30 + 15 * (len(self._paths(w)) + len(self._lines(w))) + 8

    def draw(self, s, x, y, w, registry=None):
        return s.file(x, y, w, self.title, self._lines(w), self._paths(w))


class Kernel:
    """A part of the Linux kernel"""

    def __init__(self, title, lines=(), name=None):
        self.title, self.lines, self.name = title, list(lines), name

    def _lines(self, w):
        return wrap(self.lines, w - 26)

    def height(self, w):
        return 32 + 15 * len(self._lines(w)) + 8

    def draw(self, s, x, y, w, registry=None):
        h = self.height(w)
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#f1f5f9" stroke="{KERNEL}" stroke-width="2"/>')
        s.text(x + 12, y + 21, self.title, size=13, weight="bold", fill=KERNEL)
        cy = y + 38
        for line in self._lines(w):
            s.text(x + 12, cy, line, size=11.5, fill="#334155")
            cy += 15
        return Rect(x, y, w, h)


def column_height(blocks, w):
    return sum(b.height(w) for b in blocks) + BLOCK_GAP * (len(blocks) - 1) if blocks else 0


def draw_column(s, blocks, x, y, w, registry):
    for b in blocks:
        r = b.draw(s, x, y, w, registry)
        if b.name:
            registry[b.name] = r
        y += b.height(w) + BLOCK_GAP


# --- 0. Title and legend ---

def header(s):
    s.text(40, 62, "Maia Shell — project map", size=34, weight="bold")
    s.text(40, 94, "Maia 0.2.0 · branch main · 2026-11-10 · generated by doc/diagrams/project_map.py", size=14, fill="#475569")
    intro = [
        "How to read it, like a city map:",
        "1  The start of a session: from the session file SDDM offers to the shell on the screen,",
        "    who starts whom and in which order.",
        "2  The running session in three columns, one row per subject. Left: Linux (the kernel and the",
        "    system daemons Maia talks to). Middle: Maia's own processes (services, the server) and the",
        "    QML modules through which they reach the frontends. Right: the frontends and the apps.",
        "    Most connections run straight from left to right inside their row; the Wayland display at",
        "    the top is the road every window connects to.",
        "3  Where things are: the source tree, the installation, the user's files.",
        "Every process and module names its source directory (monospace, \"→\" where it is installed);",
        "<v> is the Maia version (0.2.0), <prefix> the installation, /opt/Maia/Maia_<v>.",
    ]
    y = 132
    for i, line in enumerate(intro):
        s.text(40, y, line, size=13.5 if i else 15, weight="bold" if i == 0 else "normal", fill="#1e293b")
        y += 20
    legend(s, 1320, 40)


def legend(s, x, y):
    w, h = 2280, 300
    s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5"/>')
    s.text(x + 18, y + 28, "Legend", size=17, weight="bold")
    # Shapes
    cx, cy = x + 20, y + 50
    s.text(cx, cy, "What a shape is", size=13, weight="bold", fill="#475569")
    cy += 14
    shapes = [
        ("process", PROCESS_MAIA, "a process (own address space); the colour says whose:"),
        ("library", "#047857", "a library loaded into processes (QML module, static library)"),
        ("card", None, "a part of a process or library; the tag says what it is"),
        ("contract", None, "a contract: the API a process offers, its methods and what they do"),
        ("file", None, "a file or directory on disk"),
        ("socket", None, "a Unix socket a process listens on"),
        ("kernel", None, "a part of the Linux kernel"),
    ]
    for shape, color, text in shapes:
        if shape == "process":
            s.add(f'<rect x="{cx}" y="{cy}" width="44" height="22" rx="7" fill="{color}" fill-opacity="0.05" stroke="{color}" stroke-width="3"/>')
        elif shape == "library":
            s.add(f'<rect x="{cx}" y="{cy}" width="44" height="22" rx="7" fill="{color}" fill-opacity="0.05" stroke="{color}" stroke-width="2" stroke-dasharray="6 4"/>')
        elif shape == "card":
            s.add(f'<rect x="{cx}" y="{cy}" width="44" height="22" rx="5" fill="#ffffff" stroke="#94a3b8" stroke-width="1.5"/>')
            s.add(f'<rect x="{cx}" y="{cy}" width="5" height="22" rx="2" fill="#c2410c"/>')
        elif shape == "contract":
            s.add(f'<rect x="{cx}" y="{cy}" width="44" height="22" rx="5" fill="#faf5ff" stroke="#7c3aed" stroke-width="1.6"/>')
            s.add(f'<rect x="{cx}" y="{cy}" width="5" height="22" rx="2" fill="#7c3aed"/>')
        elif shape == "file":
            s.add(f'<path d="M{cx},{cy} h32 l12,12 v10 h-44 z" fill="#fff7ed" stroke="#ea580c" stroke-width="1.8"/>')
        elif shape == "socket":
            s.add(f'<rect x="{cx}" y="{cy + 2}" width="44" height="18" rx="9" fill="#7c3aed" fill-opacity="0.08" stroke="#7c3aed" stroke-width="1.8"/>')
        else:
            s.add(f'<rect x="{cx}" y="{cy}" width="44" height="22" rx="4" fill="#f1f5f9" stroke="{KERNEL}" stroke-width="2"/>')
        s.text(cx + 56, cy + 16, text, size=12.5)
        cy += 29
        if shape == "process":
            px = cx + 56
            for pc, label in [(PROCESS_MAIA, "Maia"), (PROCESS_SYSTEM, "Linux / KDE"),
                              (PROCESS_CLIENT, "Maia shell or app"), (PROCESS_CHILD, "tool, other program")]:
                s.add(f'<rect x="{px}" y="{cy - 2}" width="30" height="13" rx="4" fill="{pc}"/>')
                s.text(px + 36, cy + 9, label, size=12)
                px += 50 + 7.0 * len(label)
            cy += 20
    # Tags
    tx0, ty = x + 640, y + 50
    s.text(tx0, ty, "Tags on the cards", size=13, weight="bold", fill="#475569")
    ty += 16
    tags = [
        ("rust", "module of a Rust program"),
        ("cpp", "C++ class"),
        ("qml", "QML type (C++ or QML)"),
        ("qmlfile", "QML files of a shell or app"),
        ("capnp", "schema in contract/*.capnp"),
        ("dbus", "D-Bus interface from an .xml file"),
        ("dbusapi", "D-Bus name owned by the process"),
        ("system", "part of Linux / KDE"),
        ("tool", "a program used as a tool"),
    ]
    for key, text in tags:
        label, color = svgkit.KIND[key]
        tw = 10 + len(label) * 6.2
        s.tag(tx0 + tw, ty, label, color)
        s.text(tx0 + 170, ty + 13, text, size=12.5)
        ty += 25
    # Arrows, in two columns
    ax0, ay0 = x + 1060, y + 50
    s.text(ax0, ay0, "Connections", size=13, weight="bold", fill="#475569")
    items = list(svgkit.ARROW.items())
    for i, (kind, (_, _, text)) in enumerate(items):
        col, row = divmod(i, 5)
        ax, ay = ax0 + col * 600, ay0 + 22 + row * 30
        s.arrow([(ax, ay + 6), (ax + 50, ay + 6)], kind)
        s.text(ax + 64, ay + 11, text, size=12.5)
    # Note
    ny = y + 230
    notes = [
        "A connection is drawn once, from the side that calls; a two-headed arrow means calls both ways (a",
        "listener, a password prompt). What runs inside a process is in its frame; a module drawn outside of a",
        "process frame is a library: the processes that import it run its code themselves.",
    ]
    for line in notes:
        s.text(ax0, ny, line, size=12.5, fill="#334155", italic=True)
        ny += 18


# --- 1. The start of a session ---

def section_title(s, y, number, title, subtitle):
    s.add(f'<rect x="40" y="{y}" width="{W - 80}" height="54" rx="10" fill="#0f172a"/>')
    s.text(64, y + 35, f"{number}  {title}", size=22, weight="bold", fill="#ffffff")
    s.text(W - 64, y + 34, subtitle, size=14, fill="#cbd5e1", anchor="end")
    return y + 54


class Step:
    """One step of the start: a numbered box; shape is a process, a script or a file"""

    def __init__(self, num, title, what, color, paths=(), lines=(), shape="process"):
        self.num, self.title, self.what, self.color = num, title, what, color
        self.paths, self.lines, self.shape = list(paths), list(lines), shape

    def _paths(self, w):
        return wrap(self.paths, w - 30, mono=True)

    def _lines(self, w):
        return wrap(self.lines, w - 30)

    def height(self, w):
        return 70 + 15 * len(self._paths(w)) + 15 * len(self._lines(w)) + 10

    def draw(self, s, x, y, w):
        h = self.height(w)
        c = self.color
        if self.shape == "file":
            f = 18
            s.add(f'<path d="M{x},{y} h{w - f} l{f},{f} v{h - f} h{-w} z" fill="#fff7ed" stroke="#ea580c" stroke-width="2"/>')
            s.add(f'<path d="M{x + w - f},{y} v{f} h{f}" fill="none" stroke="#ea580c" stroke-width="2"/>')
            title_fill = "#9a3412"
        else:
            dash = ' stroke-dasharray="10 5"' if self.shape == "script" else ""
            s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{c}" fill-opacity="0.06" '
                  f'stroke="{c}" stroke-width="3"{dash}/>')
            title_fill = c
        s.add(f'<circle cx="{x + 24}" cy="{y + 26}" r="15" fill="{c if self.shape != "file" else "#ea580c"}"/>')
        s.text(x + 24, y + 31, str(self.num), size=14, weight="bold", fill="#ffffff", anchor="middle")
        s.text(x + 48, y + 25, self.title, size=14.5, weight="bold", fill=title_fill)
        s.text(x + 48, y + 43, self.what, size=11.5, fill="#475569", italic=True)
        cy = y + 66
        for p in self._paths(w):
            s.text(x + 14, cy, p, size=10.5, fill="#334155", mono=True)
            cy += 15
        if self.paths:
            cy += 4
        for line in self._lines(w):
            s.text(x + 14, cy, line, size=11.5, fill="#1e293b")
            cy += 15
        return Rect(x, y, w, h)


def session_start(s, y):
    y = section_title(s, y, "1", "The start of a session: who starts whom, in which order",
                      "Maia/DeployFiles/session/*.in → <prefix>/bin/; what the session runs: <prefix>/etc/maia/session.toml")
    y += 50
    cols = 8
    gap = 112
    w = (W - 80 - gap * (cols - 1)) / cols
    xs = [40 + i * (w + gap) for i in range(cols)]
    SCRIPT = "#475569"
    steps = [
        Step(1, "SDDM", "display manager · system process", PROCESS_SYSTEM,
             paths=["/usr/bin/sddm"],
             lines=["The login screen offers \"Maia 0.2.0 (KWin)\" and \"Maia 0.2.0 (Wayfire)\".",
                    "After the login (PAM, pam_kwallet5) it runs the Exec= of the chosen session file as the user."]),
        Step(2, "Session file", ".desktop file, read by SDDM", "#ea580c", shape="file",
             paths=["/usr/share/wayland-sessions/", "  maia_<v>-kwin.desktop", "  maia_<v>-wayfire.desktop",
                    "← session/maia-kwin.desktop.in"],
             lines=["Exec=<prefix>/bin/run_maia_kwin.sh (or run_maia_wayfire.sh).",
                    "install_on_ubuntu.sh copies the files there."]),
        Step(3, "Session script", "bash script · becomes the session service", SCRIPT, shape="script",
             paths=["<prefix>/bin/run_maia_kwin.sh", "<prefix>/bin/run_maia_wayfire.sh",
                    "+ maia-session-common.sh"],
             lines=["No session bus yet: exec dbus-run-session <the script> (starts dbus-daemon --session, "
                    "runs the script again inside).",
                    "maia_session_prepare: XDG_SESSION_TYPE=wayland, XDG_CURRENT_DESKTOP=KDE, the distribution's "
                    "plasma-workspace/env/*.sh, <prefix>/etc/xdg last in XDG_CONFIG_DIRS, QT_QPA_PLATFORM=wayland;xcb.",
                    "Wayfire: makes ~/.config/maia/<v>/wayfire.ini on the first start.",
                    "Output: ~/maia_<v>_kwin_session.log (or _wayfire_), for the whole session."]),
        Step(4, "maia-session-service", "the main process of the session · Rust", PROCESS_MAIA,
             paths=["<prefix>/libexec/maia-session-service", "  --compositor kwin | wayfire"],
             lines=["Reads session.toml; starts the compositor and waits for its display (at most 20 s).",
                    "Then the processes in their order; starts them again after a crash; ends the session in order.",
                    "The only part of Maia that talks to systemd-logind."]),
        None,  # the compositors, drawn below
        Step(6, "KDE's units, Maia services", "started in the order of session.toml", PROCESS_MAIA,
             paths=["kglobalacceld (Wayfire only)", "systemctl --user start plasma-kwallet-pam,",
                    "  plasma-polkit-agent, plasma-powerdevil, plasma-kaccess",
                    "<prefix>/libexec/maia-windows-service", "<prefix>/libexec/maia-network-service",
                    "<prefix>/libexec/maia-appearance-service"],
             lines=["Before the shell, so that the dock has the windows at once.",
                    "maia-appearance-service in the KWin session only (no Wayfire backend yet)."]),
        Step(7, "appMaiaServer", "the Maia server · started again after a crash", PROCESS_MAIA,
             paths=["<prefix>/bin/appMaiaServer -platform wayland"],
             lines=["Server mode: its D-Bus services (org.maia.*), then the QML engine.",
                    "MAIA_LOG_FILE=~/maia_<v>_server.log, MAIA_LOG_PORT=50001.",
                    "5 crashes in 2 minutes end the session."]),
        Step(8, "The shell", "QML of the active frontend", PROCESS_CLIENT,
             paths=["<prefix>/frontends/<name>/shell/Main.qml"],
             lines=["Loaded into appMaiaServer's QML engine (the active id is in maiarc).",
                    "MProxyWindow starts a window in its own process: appMaiaServer --mode client --source <qml> "
                    "--proxy-window-addr <socket> (the Maia frontend's LayerTop, LayerBottom)."]),
    ]
    kwin = Step(5, "KWin", "compositor · system process", PROCESS_SYSTEM,
                paths=["kwin_wayland_wrapper --xwayland", "  \"<the ready helper>\""],
                lines=["The wrapper restarts KWin after a crash, on the same sockets.",
                       "KWin starts the ready helper as an application: maia-session-service --compositor-ready "
                       "reports WAYLAND_DISPLAY and DISPLAY."])
    wayfire = Step(5, "Wayfire", "compositor · system process", PROCESS_SYSTEM,
                   paths=["wayfire -c ~/.config/maia/<v>/wayfire.ini"],
                   lines=["[autostart] runs $MAIA_SESSION_SCRIPT, which the service sets to the ready helper.",
                          "When Wayfire ends, the session ends."])
    heights = [st.height(w) for st in steps if st]
    comp_h = kwin.height(w) + 22 + wayfire.height(w)
    band_h = max(max(heights), comp_h)
    rects = {}
    for i, st in enumerate(steps):
        if st is None:
            top = y + (band_h - comp_h) / 2
            rects["kwin"] = kwin.draw(s, xs[i], top, w)
            rects["wayfire"] = wayfire.draw(s, xs[i], top + kwin.height(w) + 22, w)
            continue
        rects[i] = st.draw(s, xs[i], y + (band_h - st.height(w)) / 2, w)

    def label_before(b, y, text):
        s.text(b.x - 8, y - 9, text, size=11, weight="bold", fill="#475569", anchor="end")

    my = y + band_h / 2
    for i, text in [(0, "reads"), (1, "runs Exec="), (2, "exec"), (6, "loads")]:
        a, b = rects[i], rects[i + 1]
        s.arrow([(a.right, my), (b.x, my)], "spawn", width=2.6)
        label_before(b, my, text)
    # 1. The compositor
    a = rects[3]
    for key, text in [("kwin", "1. starts (KWin)"), ("wayfire", "1. starts (Wayfire)")]:
        b = rects[key]
        lx = a.right + 24
        s.arrow([(a.right, a.mid_y()), (lx, a.mid_y()), (lx, b.mid_y()), (b.x, b.mid_y())], "spawn", width=2.6)
        label_before(b, b.mid_y(), text)
    # The ready helper reports the display back
    c, svc = rects["wayfire"], rects[3]
    under = y + band_h + 18
    s.arrow([(c.mid_x(), c.bottom), (c.mid_x(), under), (svc.mid_x() + 40, under), (svc.mid_x() + 40, svc.bottom)],
            "socket", width=2.4)
    s.text((c.mid_x() + svc.mid_x()) / 2 + 20, under - 8, "the ready helper reports the display (session socket)",
           size=11, weight="bold", fill="#0891b2", anchor="middle")
    # 2. and 3.: the processes, after the display is known
    over = y - 22
    for target, text, dx in [(5, "2. then", -30), (6, "3. last", 30)]:
        b = rects[target]
        s.arrow([(svc.mid_x() + dx, svc.y), (svc.mid_x() + dx, over + (0 if dx < 0 else 10)),
                 (b.mid_x(), over + (0 if dx < 0 else 10)), (b.mid_x(), b.y)], "spawn", width=2.6)
        s.text(b.mid_x() + 8, over + (0 if dx < 0 else 10) + 16, text, size=11, weight="bold", fill="#475569")
    y += band_h + 44
    # The end of a session, and the development variant
    end = [
        ("The end", "Sign out in the shell: Session.logout() (Maia.Session) → session.capnp logout() → maia-session-service "
         "stops the shell, then the other processes, KDE's units and the compositor → it exits → dbus-run-session ends → "
         "SDDM shows the login screen. Power off and reboot ask logind first (maybe for the administrator's password)."),
        ("Development", "<prefix>/bin/run_maia_nested_wayland.sh runs maia-session-service with the compositor kwin-nested "
         "(a kwin_wayland window in the current session): its own session bus, the fake logind, the simulated network "
         "(MAIA_NETWORK_BACKEND=fake); the connection data in $XDG_RUNTIME_DIR/maia-nested-wayland.env."),
    ]
    bw = (W - 80 - 30) / 2
    for i, (title, text) in enumerate(end):
        x = 40 + i * (bw + 30)
        lines = wrap([text], bw - 40)
        h = 40 + 15 * len(lines) + 10
        s.add(f'<rect x="{x}" y="{y}" width="{bw}" height="{h}" rx="10" fill="#f8fafc" stroke="#94a3b8" stroke-width="1.5"/>')
        s.text(x + 18, y + 26, title, size=14.5, weight="bold")
        cy = y + 46
        for line in lines:
            s.text(x + 18, cy, line, size=12, fill="#1e293b")
            cy += 15
        end_h = h
    return y + end_h


# --- 2. The running session ---

def rows():
    """Each row: the blocks of every column; ENGINE holds the card of the QML engine in that row"""
    windows = dict(
        kernel=[Kernel("DRM / KMS, input", ["/dev/dri/card*, renderD*: screens, GPU buffers",
                                            "/dev/input/event*: keyboard, mouse (libinput)",
                                            "opened through logind (the seat)"], name="k_drm")],
        linux=[
            Process("Compositor", "system process · KWin or Wayfire", PROCESS_SYSTEM, name="compositor", children=[
                Card("KWin session", "system", [
                    "kwin_wayland_wrapper → kwin_wayland --xwayland",
                    "built in: kglobalacceld (org.kde.kglobalaccel)",
                    "privileged protocols: KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 (dev)"], path="/usr/bin/kwin_wayland"),
                Card("Wayfire session", "system", [
                    "wayfire -c ~/.config/maia/<v>/wayfire.ini",
                    "plugins from other repositories: aurorae (KDE Aurorae decorations), "
                    "plasma-window-management (the window list for Maia)",
                    "blur plugin: blurs a window where it is translucent"], path="/usr/bin/wayfire + plugin directory"),
                Card("Wayland protocols Maia uses", "system", [
                    "xdg-shell: the windows of applications",
                    "zwlr_layer_shell_v1: the shell's layers (LayerShellQt)",
                    "org_kde_plasma_window_management: the window list",
                    "org_kde_kwin_blur: blur behind a window (MWindowBlur)",
                    "Xwayland: X11 applications (DISPLAY)"]),
                Contract("org.kde.KWin", "dbusapi", None, [
                    ("/KWin", "KWin only", [("reloadConfig", "signal: re-read kwinrc"),
                                            ("supportInformation()", "what KWin really loaded")]),
                    ("/Effects", "org.kde.kwin.Effects", [("unloadEffect(name)", "")])], name="kwin_dbus"),
            ]),
            File("wayfire.ini", ["~/.config/maia/<v>/wayfire.ini"],
                 ["Wayfire session only: plugins, keys, [autostart] → phase 2", "made from <prefix>/etc/maia/wayfire.ini"],
                 name="wayfire_ini"),
        ],
        service=[
            Process("maia-windows-service", "Maia service · Rust", PROCESS_MAIA,
                    path="Maia/services/windows/service/ → <prefix>/libexec/", name="windows", children=[
                        Card("kwin.rs: the compositor backend", "rust", [
                            "a client of org_kde_plasma_window_management",
                            "every window as one Window: title, app id, icon, states, geometry",
                            "commands become requests on the window object"]),
                        Card("apps.rs, launch.rs: applications", "rust", [
                            "which application a window belongs to: desktop entries "
                            "(app id, StartupWMClass, /proc/<pid>/exe)",
                            "starts applications from Exec=, in their own process group"]),
                        Contract("windows.capnp", "capnp", "Maia/services/windows/contract/", [
                            ("WindowService", "", [("watch(listener)", "snapshot, then added / changed / removed"),
                                                   ("control()", "→ WindowControl"),
                                                   ("icon(id), info()", "")]),
                            ("WindowControl", "", [("activate(id), close(id)", ""),
                                                   ("setMinimized / setMaximized / setFullscreen", ""),
                                                   ("setKeepAbove / setKeepBelow", ""),
                                                   ("requestMove(id), requestResize(id)", "by the compositor"),
                                                   ("launch(launcherUrl)", "start an app (applications:….desktop)"),
                                                   ("launchNewInstance(id)", "the window's app once more")])]),
                        Socket("$XDG_RUNTIME_DIR/maia/windows-$WAYLAND_DISPLAY.sock", name="windows_sock"),
                    ]),
            File("Desktop entries", ["$XDG_DATA_HOME/applications/*.desktop", "$XDG_DATA_DIRS/*/applications/*.desktop"],
                 ["read: the names, icons and Exec= of the applications"], name="desktop_entries"),
        ],
        module=[
            Process("Maia.Windows", "QML module · C++", "#047857", library=True,
                    path="Maia/services/windows/qml/ → <prefix>/lib/…/qml6/Maia/Windows/", name="m_windows", children=[
                        Card("TasksModel", "qml", [
                            "windows and pinned launchers, grouped like Plasma's TasksModel",
                            "activate, close, minimize, … launch, launchNewInstance",
                            "ServiceConnection: the Cap'n Proto client; reconnects every second"]),
                    ]),
        ],
        engine=Card("Dock, taskbar", "qmlfile", [
            "Lumen taskbar, Maia dock (LayerBottom), XPLuna taskbar, Ubuntu dock",
            "TasksModel: running windows and pinned apps"], path="<frontend>/shell/dock/, taskbar/", name="e_dock"),
        right=[
            Process("Applications", "any Wayland or X11 program", PROCESS_CHILD, name="apps", children=[
                Card("Konsole, Firefox, …", "system", [
                    "started by TasksModel.launch (maia-windows-service) or backend.startApplication / runCommand",
                    "their windows reach the dock through the compositor and maia-windows-service"]),
            ]),
        ],
    )
    appearance = dict(
        kernel=[Kernel("inotify", ["file change events: maia-appearance-service notices what KDE's own "
                                   "settings change in ~/.config and in the theme directories"])],
        linux=[
            File("kwinrc", ["~/.config/kwinrc"], ["[org.kde.kdecoration2] library, theme, BorderSize",
                                                  "read by KWin; written by maia-appearance-service and by KDE's "
                                                  "System Settings"], name="kwinrc"),
            Process("kwriteconfig6", "tool · child process", PROCESS_CHILD, name="kwriteconfig",
                    note="writes kwinrc with KConfig's locking and escaping"),
            File("Window decoration themes", [
                "~/.local/share/aurorae/themes/<name>/",
                "<prefix>/share/aurorae/themes/ (Se7enAero, XBoomer)",
                "/usr/share/aurorae/themes/, /usr/share/kwin/decorations/",
                "<qt plugins>/org.kde.kdecoration3/*.so"],
                ["read by KWin and by Wayfire's aurorae plugin"], name="themes"),
            File("kdeglobals", ["~/.config/kdeglobals"], ["KDE's colour scheme; MKdeColorScheme (Maia.Backend) writes it"]),
        ],
        service=[
            Process("maia-appearance-service", "Maia service · Rust · KWin session only", PROCESS_MAIA,
                    path="Maia/services/appearance/service/ → <prefix>/libexec/", name="appearance", children=[
                        Card("compositor/kwin.rs", "rust", [
                            "writes kwinrc (kwriteconfig6), then tells KWin: D-Bus /KWin reloadConfig",
                            "checks what KWin loaded: supportInformation()",
                            "compositor/fake.rs: in memory, for the tests"]),
                        Card("decorations/", "rust", [
                            "catalog.rs: the themes on disk (Aurorae SVG and QML, KDecoration plugins)",
                            "install.rs: installs an Aurorae theme from an archive, checked first",
                            "frontends.rs: the decoration of every frontend (appearance.json)",
                            "inotify.rs: notices changes made by other programs"]),
                        Contract("appearance.capnp, decorations.capnp", "capnp", "Maia/services/appearance/contract/", [
                            ("AppearanceService", "", [("decorations()", "→ Decorations"), ("info()", "")]),
                            ("Decorations", "", [("list(), current(), capabilities()", ""),
                                                 ("watch(listener)", "snapshot, themesChanged, currentChanged"),
                                                 ("set(themeId), setBorderSize(size)", "change the decoration"),
                                                 ("install(path), remove(themeId)", "the user's own themes"),
                                                 ("activateFrontend(frontend, defaultThemeId)", "the frontend's choice"),
                                                 ("refresh()", "")])]),
                        Socket("$XDG_RUNTIME_DIR/maia/appearance-$WAYLAND_DISPLAY.sock", name="appearance_sock"),
                    ]),
            File("appearance.json", ["~/.config/maia/<v>/appearance.json"], ["the decoration chosen in every frontend"],
                 name="appearance_json"),
        ],
        module=[
            Process("Maia.Appearance", "QML module · C++", "#047857", library=True,
                    path="Maia/services/appearance/qml/ → <prefix>/lib/…/qml6/Maia/Appearance/", name="m_appearance",
                    children=[
                        Card("WindowDecorations", "qml", ["the decoration themes: set, install, remove"]),
                        Card("FrontendLook", "qml", ["when a frontend loads, gives the windows its own decoration "
                                                     "(activateFrontend)"]),
                    ]),
        ],
        engine=Card("Window decorations of the frontend", "qmlfile", [
            "FrontendLook in shell/Main.qml: XPLuna → XBoomer, the others their own",
            "a chooser of decorations (WindowDecorations)"], name="e_look"),
        right=[
            Process("appMaiaServer --mode client", "Maia shell · a process per MProxyWindow", PROCESS_CLIENT,
                    path="<frontend>/shell/LayerTop.qml, LayerBottom.qml (Maia frontend)", name="client", children=[
                        Card("A window of the shell in its own process", "qmlfile", [
                            "started by MProxyWindow: --source <qml> --proxy-window-addr <socket>",
                            "QLocalSocket to ProxyWindowLocalServer: geometry, visibility",
                            "imports the same modules as the shell (Maia.Windows, Maia.Network, …)"]),
                    ]),
        ],
    )
    network = dict(
        kernel=[Kernel("Wi-Fi driver, cfg80211", ["nl80211: scans, association; WPA through wpa_supplicant"],
                       name="k_wifi")],
        linux=[
            Process("NetworkManager", "system process · root · system D-Bus", PROCESS_SYSTEM, name="nm", children=[
                Contract("org.freedesktop.NetworkManager", "dbusapi", None, [
                    ("Manager, Device, AccessPoint", "", [("WirelessEnabled, ActivateConnection, …", "state, commands")]),
                    ("Settings", "", [("AddConnection, Update, Delete", "saved profiles")]),
                    ("AgentManager", "", [("Register()", "the session's secret agent"),
                                          ("→ SecretAgent.GetSecrets", "when a password is missing")])]),
                Card("wpa_supplicant, polkitd", "system", [
                    "wpa_supplicant: the WPA handshake with the Wi-Fi driver",
                    "polkitd: authorizes changes; plasma-polkit-agent asks for the password"]),
            ]),
            File("Saved networks", ["/etc/NetworkManager/system-connections/*.nmconnection"],
                 ["profiles with their secrets, readable by root only"], name="nm_profiles"),
        ],
        service=[
            Process("maia-network-service", "Maia service · Rust", PROCESS_MAIA,
                    path="Maia/services/network/service/ → <prefix>/libexec/", name="network", children=[
                        Card("nm.rs, fake.rs: the backends", "rust", [
                            "nm.rs: NetworkManager on the system D-Bus (zbus): follows its signals, re-reads objects",
                            "fake.rs: a simulated network (MAIA_NETWORK_BACKEND=fake: tests, nested sessions)"]),
                        Card("agent.rs, prompt.rs: the secret agent", "rust", [
                            "the session's only NetworkManager agent: asks the shell for passwords",
                            "keeps nothing: NetworkManager saves the secrets in the profile"]),
                        Contract("network.capnp", "capnp", "Maia/services/network/contract/network.capnp", [
                            ("NetworkService", "", [("watch(listener)", "snapshot, then every change"),
                                                    ("control()", "→ NetworkControl"),
                                                    ("registerPrompter(prompter)", "the shell answers passwords")]),
                            ("NetworkControl", "", [("setWirelessEnabled(enabled)", "Wi-Fi on / off"),
                                                    ("requestScan(deviceId)", "look for networks"),
                                                    ("connect(networkId), activate(uuid, …)", "join a network"),
                                                    ("connectWithSettings(…), disconnect(…)", ""),
                                                    ("forget(uuid)", "remove a saved network"),
                                                    ("settings / updateSettings / secrets", "a profile's details"),
                                                    ("qrCode(uuid)", "share a network"),
                                                    ("startHotspot / stopHotspot", "personal hotspot"),
                                                    ("checkConnectivity()", "captive portal")]),
                            ("SecretPrompter", "implemented by the shell", [("ask(request), cancel(id)",
                                                                             "the password dialog")])]),
                        Socket("$XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock", name="network_sock"),
                    ]),
        ],
        module=[
            Process("Maia.Network", "QML module · C++", "#047857", library=True,
                    path="Maia/services/network/qml/ → <prefix>/lib/…/qml6/Maia/Network/", name="m_network", children=[
                        Card("WifiStatus", "qml", ["Wi-Fi on / off, the connected network, the signal"]),
                        Card("The network models", "qml",
                             ["WifiNetworksModel: networks in reach", "WifiDevicesModel: the adapters",
                              "SavedNetworksModel: saved networks"]),
                        Card("NetworkControl", "qml", ["the commands: connect, forget, hotspot, …"]),
                        Card("SecretPrompt, QrCodeView", "qml", [
                            "SecretPrompt: answers the password requests (one per session: active: true)",
                            "QrCodeView: draws the QR code of a network"]),
                    ]),
        ],
        engine=Card("Wi-Fi in the shell", "qmlfile", [
            "Lumen's quick settings, the Maia frontend's Control Center",
            "WifiStatus, WifiNetworksModel: the switch, the list, connecting",
            "SecretPrompt: the password dialog of the session"], name="e_wifi"),
        right=[
            Process("maia-settings", "Maia app · C++ / QML", PROCESS_CLIENT,
                    path="apps/settings/ → <prefix>/bin/maia-settings [--page network]", name="settings", children=[
                        Card("Maia.SettingsKit", "qml", [
                            "the frame: navigation with search, SettingsPage, dialogs, toasts; compiled in"],
                             path="apps/settings/qml/"),
                        Card("Pages", "qmlfile", [
                            "pages/<id>/: metadata.json and QML, read at run time",
                            "network: the Wi-Fi page (imports Maia.Network)"],
                             path="apps/settings/pages/ → <prefix>/share/maia-settings/pages/"),
                        Card("One window, Lumen's look", "qml", [
                            "a second start hands its --page over and quits",
                            "imports LumenFrontend: the theme and components of Lumen"]),
                    ]),
        ],
    )
    session = dict(
        kernel=[Kernel("Power management", ["ACPI, /sys/power: suspend, reboot, power off for logind"],
                       name="k_power")],
        linux=[
            Process("systemd-logind", "system process · system D-Bus", PROCESS_SYSTEM, name="logind", children=[
                Contract("org.freedesktop.login1", "dbusapi", None, [
                    ("Manager", "", [("PowerOff, Reboot, Suspend, Hibernate, …", "interactive: polkit may ask"),
                                     ("CanPowerOff, CanReboot, CanSuspend, …", "yes / no / challenge"),
                                     ("PrepareForSleep, PrepareForShutdown", "signals")])]),
                Card("The seat", "system", ["gives the compositor the GPU and the input devices"]),
            ]),
        ],
        service=[
            Process("maia-session-service", "Maia service · Rust · the main process of the session", PROCESS_MAIA,
                    path="Maia/services/session/service/ → <prefix>/libexec/", name="sessionsvc", children=[
                        Card("session.rs, policy.rs, procs.rs", "rust", [
                            "starts everything of session.toml in its order (section 1), each in its own process group",
                            "a crashed child comes back after 1 s, 2 s, 4 s… (the shell: 5 crashes in 2 min end the session)",
                            "ends the session in order: the shell, the others, KDE's units, the compositor",
                            "children get SIGTERM if the service dies (PDEATHSIG); it reaps orphans (subreaper)"]),
                        Card("power.rs: logind", "rust", [
                            "the only part of Maia that talks to org.freedesktop.login1 (zbus)",
                            "fake: MAIA_SESSION_BACKEND=fake (tests, nested sessions) logs, never acts"]),
                        Contract("session.capnp", "capnp", "Maia/services/session/contract/session.capnp", [
                            ("SessionService", "", [("watch(listener)", "state, ending, capabilities, children"),
                                                    ("control()", "→ SessionControl"),
                                                    ("compositorReady(environment)", "the ready helper")]),
                            ("SessionControl", "", [("logout()", "end the session"),
                                                    ("powerOff(), reboot()", "logind first, then the end"),
                                                    ("suspend(), hibernate(), …", "sleep"),
                                                    ("restartChild(name)", "start a child again by hand")])]),
                        Socket("$MAIA_SESSION_SOCKET (session-$XDG_SESSION_ID.sock)", name="session_sock"),
                    ]),
            File("session.toml", ["<prefix>/etc/maia/session.toml"], [
                "the compositors and the processes of a session: order, restarts, limits; one per Maia version"],
                 name="session_toml"),
        ],
        module=[
            Process("Maia.Session", "QML module · C++", "#047857", library=True,
                    path="Maia/services/session/qml/ → <prefix>/lib/…/qml6/Maia/Session/", name="m_session", children=[
                        Card("Session (singleton)", "qml", [
                            "state, endingAction; canLogout, canPowerOff, canReboot, canSuspend, …",
                            "logout(), powerOff(), reboot(), suspend(), …; actionFailed(action, error)"]),
                        Card("SessionChildrenModel", "qml", ["the processes of the session, their state and restarts"]),
                    ]),
        ],
        engine=Card("The session menu", "qmlfile", [
            "Lumen's power menu, the Maia frontend's session screen, XPLuna's log off / turn off,",
            "Ubuntu's control board: Session.canPowerOff, Session.logout(), …"], name="e_session"),
        right=[],
    )
    server = dict(
        kernel=[],
        linux=[
            Process("dbus-daemon", "system processes · the two buses", PROCESS_SYSTEM, children=[
                Card("System bus", "system", ["/run/dbus/system_bus_socket: NetworkManager, logind, polkit"]),
                Card("Session bus", "system", ["started by dbus-run-session (session script, phase 1)",
                                               "org.maia.*, org.kde.*: everything of the user's session"]),
            ]),
        ],
        service=[
            Process("appMaiaServer — the server core", "Maia server · C++ · one process with the shell →",
                    PROCESS_MAIA, path="Maia/MaiaServerApp/, Maia/BackendLib/server/ → <prefix>/bin/appMaiaServer",
                    name="core", children=[
                        Contract("org.maia.FrontendManager", "dbus", "Maia/BackendLib/dbus/org.maia.FrontendManager.xml", [
                            ("/FrontendManager", "FrontendManagerService", [
                                ("getFrontendList()", "id, name, path, rootPath, active"),
                                ("activeFrontend(), setActiveFrontend(id)", "switch the shell"),
                                ("activeFrontendChanged, frontendAdded, …", "signals")])]),
                        Contract("The other D-Bus services", "dbusapi", "Maia/BackendLib/server/*Service.cpp", [
                            ("org.maia.FavoriteApplications", "", [
                                ("addFavorite(id), removeFavorite(id)", ""),
                                ("getFavorites(); favoritesChanged", "pinned apps")]),
                            ("com.maia.LocaleSettings", "", [("twentyFourTime", "property: 24-hour clock")]),
                            ("org.maia.WindowManagerX11Service", "", [
                                ("unloadEffect(name), reconfigure()", "→ org.kde.KWin")])]),
                        Card("FrontendLoader, QmlGui", "cpp", [
                            "loads <frontend>/shell/Main.qml into the QML engine (right)",
                            "a switch: unload, KWin reconfigure, load the new one (GuiManagerStateMachine.scxml)"]),
                        Card("What the QML engine gets", "cpp", [
                            "backend: startApplication, runCommand, startProcess, installIconTheme",
                            "audioBackend (MAudioBackend, KF6::PulseAudioQt): volume, mute",
                            "appsListModel: the installed apps; image://icontheme, image://backend_app_icon"],
                             name="core_context"),
                        Card("ProxyWindowLocalServer, Logger", "cpp", [
                            "a local socket for the client processes of MProxyWindow",
                            "Logger: ~/maia_<v>_server.log, WebSocket :50001 for appLogger"], name="core_logger"),
                    ]),
            File("Settings of the shell", ["~/.config/maia/<v>/maiarc", "~/.config/maia/<v>/maia.conf"], [
                "maiarc (KConfig): the active frontend, the 24-hour clock",
                "maia.conf (QSettings, QML Settings {}): the favourites, and what the frontends keep "
                "(LumenFrontend, MaiaDock, MaiaControlCenter, …)"], name="shell_conf"),
        ],
        module=[
            Process("Maia.Backend", "QML module · static, compiled into appMaiaServer", "#047857", library=True,
                    path="Maia/BackendLib/, Maia/ClientLib/", name="m_backend", children=[
                        Card("Session and frontends", "qml", [
                            "MFrontendModel: the frontends, the switch (D-Bus FrontendManager)",
                            "MFavoritesAppsModel, MLocaleSettings: D-Bus FavoriteApplications, LocaleSettings"]),
                        Card("Windows of the shell", "qml", [
                            "MProxyWindow: a window in its own process (appMaiaServer --mode client)",
                            "MaskArea, MMaskedItem: the input regions of the layer windows",
                            "MWindowBlur: blur behind a window (KWindowEffects)",
                            "MKdeColorScheme: KDE's colour scheme (kdeglobals)",
                            "MWindowManagerX11, MIconItem, ThemesModel: older helpers"]),
                    ]),
            Process("Maia::FrontendModules, Maia::Paths", "static C++ libraries", "#1d4ed8", library=True,
                    path="Maia/FrontendModules/, Maia/Paths/", children=[
                        Card("Used by appMaiaServer and maia-settings", "cpp", [
                            "FrontendModules: $XDG_RUNTIME_DIR/maia/qml-modules-<pid>/<URI> → the frontend "
                            "directory, so that \"import LumenFrontend\" works",
                            "Paths: ~/.config/maia/<v>/ for every component"]),
                    ]),
        ],
        engine=[Card("shell/Main.qml of the active frontend", "qmlfile", [
            "layer windows: import org.kde.layershell (LayerShellQt)",
            "the frontend switcher: MFrontendModel; the session menu: Session (Maia.Session)",
            "Maia frontend: LayerTop, LayerBottom in MProxyWindow processes",
            "import <URI>Frontend: its theme and components"], name="e_main"),
                Card("The parts of every frontend's shell", "qmlfile", [
                    "Lumen: windows/ (taskbar, start menu, quick settings, calendar, widgets), desktop/, services/, state/",
                    "Maia: dock/, controlcenter/, library/ (App Library), menu/, session/, status/",
                    "Ubuntu 24.04: toppanel/, dock/, launcher/, controlboard/, desktop/",
                    "XPLuna: taskbar/, startmenu/, desktop/, volume/, session/",
                    "Experimental: test windows"], path="Maia/frontends/<name>/shell/")],
        right=[
            File("Frontends", ["Maia/frontends/<name>/ → <prefix>/frontends/<name>/"], [
                "qmldir: module <URI>Frontend (theme, components)",
                "shell/Main.qml: where the shell starts",
                "theme/, assets/, apps/<app>/ (the faces of apps)",
                "Lumen (LumenFrontend), Maia (MaiaFrontend), Ubuntu 24.04 (GnomeFrontend), "
                "XPLuna (XPLunaFrontend), Experimental"], name="frontends"),
        ],
    )
    rest = dict(
        kernel=[Kernel("ALSA", ["/dev/snd/*: the sound devices, used by PipeWire"], name="k_alsa")],
        linux=[
            Process("PipeWire", "user processes", PROCESS_SYSTEM, name="pipewire", children=[
                Card("pipewire, wireplumber, pipewire-pulse", "system", [
                    "PulseAudio protocol: $XDG_RUNTIME_DIR/pulse/native"]),
            ]),
            Process("KDE session services", "user processes · systemd --user", PROCESS_SYSTEM, name="kde", children=[
                Card("Started by the session script", "system", [
                    "plasma-kwallet-pam: unlocks KWallet with the login password",
                    "plasma-polkit-agent: administrator password dialogs",
                    "plasma-powerdevil: power, brightness, battery",
                    "plasma-kaccess: accessibility",
                    "kglobalacceld: Wayfire session only (KWin has it built in)"]),
                Card("kded6", "system", ["started by D-Bus activation; its networkmanagement module stays off"]),
            ]),
            File("Maia's defaults for KDE", ["<prefix>/etc/xdg/kded6rc", "<prefix>/etc/xdg/kwalletrc"], [
                "kded6rc: networkmanagement autoload=false (Maia's agent answers)",
                "kwalletrc: KDE Wallet off; last in XDG_CONFIG_DIRS"], name="kde_defaults"),
        ],
        service=[
            Process("appLogger", "developer tool · C++ / QML", PROCESS_CHILD,
                    path="Maia/LoggerApp/ → <prefix>/bin/appLogger, run_logger.sh", name="logger", children=[
                        Card("WebSocket server :50001", "cpp", ["shows the log of appMaiaServer as it is written"]),
                    ]),
            File("Logs", ["~/maia_<v>_server.log", "~/maia_<v>_kwin_session.log, ~/maia_<v>_wayfire_session.log"], [
                "the server's log; the session script with the compositor's output"], name="logs"),
        ],
        module=[],
        engine=None,
        right=[
            Process("calculator", "prototype · Rust", PROCESS_CHILD, path="apps/calculator/backend/", name="calc",
                    children=[
                        Card("A calculator service", "rust", [
                            "engine, numbers, memory; $XDG_RUNTIME_DIR/test-ipc-calculator.sock",
                            "its window is not in this repository; the session does not start it"]),
                    ]),
        ],
    )
    return [windows, appearance, network, session, server, rest]


ENGINE_HEAD = 76
# The rows the QML engine frame covers end with this one (the server)
SERVER_ROW = 4


def running_session(s, y):
    y = section_title(s, y, "2", "The running session: Linux  ↔  Maia services  ↔  frontends",
                      "one row per subject; most connections run straight from left to right")
    y += 24
    # Column titles
    for x, w, title, sub in [
        (KX, KW, "Linux kernel", "devices, system calls"),
        (LX, LW, "Linux: system and session daemons", "not Maia: what Maia talks to"),
        (SX, SW, "Maia: services and the server", "Maia's processes and their contracts"),
        (QX, QW, "Maia: QML modules", "how the frontends reach the services"),
        (EX, EW, "The shell: appMaiaServer's QML engine", "the active frontend, by subject"),
        (RX, RW, "Apps, shell windows, frontends", "other processes and files of the GUI"),
    ]:
        s.column_title(x, y + 18, w, title, sub)
    y += 64
    # The Wayland display: the road at the top
    road_y = y
    road_h = 44
    s.add(f'<rect x="{LX}" y="{road_y}" width="{RX + RW - LX}" height="{road_h}" rx="22" fill="#16a34a" fill-opacity="0.10" '
          f'stroke="#16a34a" stroke-width="2.5"/>')
    s.text(LX + 24, road_y + 28, "Wayland display  $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY", size=15, weight="bold", fill="#15803d")
    s.text(LX + 470, road_y + 28, "served by the compositor; every window of the session is its client "
           "(also maia-settings and the client processes of the shell)", size=12.5, fill="#14532d")
    y += road_h + 56
    reg = {}
    data = rows()
    row_tops = []
    engine_cards = []
    for i, row in enumerate(data):
        eh = 0
        cards = row["engine"] if isinstance(row["engine"], list) else ([row["engine"]] if row["engine"] else [])
        if cards:
            eh = sum(c.height(EW - 2 * PAD) for c in cards) + GAP * (len(cards) - 1) + (ENGINE_HEAD if i == 0 else 0)
            if i == SERVER_ROW:
                eh += PAD
        h = max(column_height(row["kernel"], KW), column_height(row["linux"], LW),
                column_height(row["service"], SW), column_height(row["module"], QW),
                column_height(row["right"], RW), eh)
        row_tops.append((y, h))
        # A faint band behind the row, with its subject
        draw_column(s, row["kernel"], KX, y, KW, reg)
        draw_column(s, row["linux"], LX, y, LW, reg)
        draw_column(s, row["service"], SX, y, SW, reg)
        draw_column(s, row["module"], QX, y, QW, reg)
        draw_column(s, row["right"], RX, y, RW, reg)
        cy = y + (ENGINE_HEAD if i == 0 else 0)
        for c in cards:
            engine_cards.append((c, cy))
            cy += c.height(EW - 2 * PAD) + GAP
        y += h + 60
    # The QML engine: one process frame over the rows of its cards
    top = row_tops[0][0]
    bottom = row_tops[SERVER_ROW][0] + row_tops[SERVER_ROW][1]
    engine = Process("appMaiaServer — the QML engine", "the shell · same process as the core ←", PROCESS_CLIENT,
                     path="<prefix>/frontends/<active>/shell/Main.qml, started by FrontendLoader")
    reg["engine"] = engine.draw_frame(s, EX, top, EW, bottom - top)
    for card, cy in engine_cards:
        r = card.draw(s, EX + PAD, cy, EW - 2 * PAD)
        if card.name:
            reg[card.name] = r
    connections(s, reg, road_y, road_h, row_tops)
    return y


def connections(s, r, road_y, road_h, row_tops):
    road_bottom = road_y + road_h
    # Wayland: down from the road to its clients, and to the compositor that serves it
    for key, dx, label in [("compositor", 0.5, "serves the display"),
                           ("windows", 0.5, "org_kde_plasma_window_management"),
                           ("engine", 0.5, "layer-shell, blur, xdg-shell"),
                           ("apps", 0.5, "xdg-shell, Xwayland")]:
        b = r[key]
        x = b.x + b.w * dx
        both = key == "compositor"
        s.arrow([(x, road_bottom), (x, b.y)], "wayland", both=both, width=2.6, label=label,
                label_at=(x + 8, road_bottom + 24))
    # The kernel, to the left of the daemons
    for a, k, dy, label in [("compositor", "k_drm", -40, "DRM, evdev"), ("nm", "k_wifi", 0, "nl80211"),
                            ("logind", "k_power", 0, "suspend, power off"), ("pipewire", "k_alsa", 0, "ALSA")]:
        a_r, k_r = r[a], r[k]
        y = min(a_r.mid_y(dy), k_r.bottom - 10) if a == "compositor" else k_r.mid_y()
        s.arrow([(a_r.x, y), (k_r.right, y)], "kernel")
    # The compositor reads its files
    comp, wini = r["compositor"], r["wayfire_ini"]
    s.arrow([(wini.mid_x(), comp.bottom), (wini.mid_x(), wini.y)], "file", label="reads (Wayfire)",
            label_at=(wini.mid_x() + 8, (comp.bottom + wini.y) / 2 + 4))
    kwinrc, themes = r["kwinrc"], r["themes"]
    lane = LX - 16
    s.arrow([(comp.x, comp.bottom - 30), (lane, comp.bottom - 30), (lane, kwinrc.mid_y()), (kwinrc.x, kwinrc.mid_y())],
            "file", label="reads", label_at=(lane - 4, kwinrc.mid_y() - 8), label_anchor="end")
    s.arrow([(lane, kwinrc.mid_y()), (lane, themes.mid_y()), (themes.x, themes.mid_y())], "file")
    # maia-appearance-service: KWin's D-Bus (top), kwriteconfig6, the themes, its own file
    app, kdbus, kwrite = r["appearance"], r["kwin_dbus"], r["kwriteconfig"]
    lane = 1088
    y0 = app.y + 22
    s.arrow([(app.x, y0), (lane, y0), (lane, kdbus.mid_y()), (comp.right, kdbus.mid_y())], "dbus",
            label="reloadConfig,\nsupportInformation", label_at=(comp.right + 8, kdbus.mid_y() - 22))
    lane = 1046
    s.arrow([(app.x, app.y + 120), (lane, app.y + 120), (lane, kwrite.mid_y()), (kwrite.right, kwrite.mid_y())], "spawn",
            label="runs", label_at=(kwrite.right + 6, kwrite.mid_y() - 8))
    s.arrow([(kwrite.mid_x(), kwrite.y), (kwrite.mid_x(), kwinrc.bottom)], "file", label="writes",
            label_at=(kwrite.mid_x() + 8, (kwrite.y + kwinrc.bottom) / 2 + 4))
    s.arrow([(app.x, app.y + 150), (lane + 20, app.y + 150), (lane + 20, themes.mid_y()), (themes.right, themes.mid_y())],
            "file", label="reads, installs themes", label_at=(themes.right + 6, themes.mid_y() - 8))
    aj = r["appearance_json"]
    s.arrow([(aj.mid_x(), app.bottom), (aj.mid_x(), aj.y)], "file", label="reads, writes",
            label_at=(aj.mid_x() + 8, (app.bottom + aj.y) / 2 + 4))
    # maia-windows-service reads the desktop entries
    win, de = r["windows"], r["desktop_entries"]
    s.arrow([(de.mid_x(), win.bottom), (de.mid_x(), de.y)], "file", label="reads",
            label_at=(de.mid_x() + 8, (win.bottom + de.y) / 2 + 4))
    # maia-network-service and NetworkManager, both ways (commands; GetSecrets back)
    net, nm = r["network"], r["nm"]
    y = nm.y + 110
    s.arrow([(net.x, y), (nm.right, y)], "dbussys", both=True, label="NetworkManager,\nSecretAgent",
            label_at=(nm.right + 12, y - 22))
    nmp = r["nm_profiles"]
    s.arrow([(nmp.mid_x(), nm.bottom), (nmp.mid_x(), nmp.y)], "file", label="keeps the profiles",
            label_at=(nmp.mid_x() + 8, (nm.bottom + nmp.y) / 2 + 4))
    # The session service and logind (system bus); session.toml
    svc, logind = r["sessionsvc"], r["logind"]
    y = logind.mid_y(-20)
    s.arrow([(svc.x, y), (logind.right, y)], "dbussys", both=True, label="PowerOff, Reboot,\nPrepareForSleep",
            label_at=(logind.right + 12, y - 22))
    toml = r["session_toml"]
    s.arrow([(toml.mid_x(), svc.bottom), (toml.mid_x(), toml.y)], "file", label="reads at the start",
            label_at=(toml.mid_x() + 8, (svc.bottom + toml.y) / 2 + 4))
    # The server core: PipeWire, its files, the logger
    core = r["core"]
    ctx, pw = r["core_context"], r["pipewire"]
    lane = 1000
    s.arrow([(core.x, ctx.mid_y()), (lane, ctx.mid_y()), (lane, pw.mid_y()), (pw.right, pw.mid_y())], "pulse",
            label="audioBackend:\nvolume, mute", label_at=(pw.right + 8, pw.mid_y() - 30))
    conf = r["shell_conf"]
    s.arrow([(conf.mid_x(), core.bottom), (conf.mid_x(), conf.y)], "file", label="reads, writes",
            label_at=(conf.mid_x() + 8, (core.bottom + conf.y) / 2 + 4))
    lg, logger = r["core_logger"], r["logger"]
    lane = 1060
    s.arrow([(core.x, lg.mid_y()), (lane, lg.mid_y()), (lane, logger.mid_y()), (logger.x, logger.mid_y())], "socket",
            label="WebSocket\n:50001", label_at=(logger.x - 8, logger.mid_y() + 20), label_anchor="end")
    # Cap'n Proto: each QML module is a client of its service
    lane = 1742
    for sock, mod in [("windows_sock", "m_windows"), ("appearance_sock", "m_appearance"), ("network_sock", "m_network"),
                      ("session_sock", "m_session")]:
        a, b = r[sock], r[mod]
        y = b.y + 60
        s.arrow([(b.x, y), (lane, y), (lane, a.mid_y()), (a.right, a.mid_y())], "capnp", both=True, width=2.6)
        s.text(b.x - 6, y - 9, "Cap'n Proto", size=11, weight="bold", fill="#7c3aed", anchor="end")
    # D-Bus between Maia.Backend (in the shell) and the services of the core
    a, b = r["core"], r["m_backend"]
    y = b.mid_y()
    s.arrow([(b.x, y), (a.right, y)], "dbus", both=True, width=2.6)
    s.text(b.x - 6, y - 9, "org.maia.*", size=11, weight="bold", fill="#2563eb", anchor="end")
    # QML imports: the modules are loaded into the shell
    for mod, card in [("m_windows", "e_dock"), ("m_appearance", "e_look"), ("m_network", "e_wifi"),
                      ("m_session", "e_session"), ("m_backend", "e_main")]:
        a, b = r[mod], r[card]
        y = b.mid_y()
        if a.y + 30 < y < a.bottom - 10:
            s.arrow([(a.right, y), (b.x, y)], "import", width=2.4, label="import", label_at=(a.right + 8, y - 9))
        else:
            ay = a.mid_y()
            lx = (a.right + EX) / 2
            s.arrow([(a.right, ay), (lx, ay), (lx, y), (b.x, y)], "import", width=2.4, label="import",
                    label_at=(a.right + 8, ay - 9))
    # The shell starts its client processes, and loads the frontend's files
    main, client, fr = r["e_main"], r["client"], r["frontends"]
    lane = 3010
    s.arrow([(main.right, main.mid_y(-20)), (lane, main.mid_y(-20)), (lane, client.mid_y()), (client.x, client.mid_y())],
            "spawn", width=2.4)
    ly = (main.mid_y(-20) + client.mid_y()) / 2
    s.add(f'<rect x="{lane - 9}" y="{ly - 75}" width="18" height="150" fill="#ffffff"/>')
    s.add(f'<text x="{lane + 4}" y="{ly}" font-family="{svgkit.FONT}" font-size="11.5" font-weight="bold" fill="#475569" '
          f'text-anchor="middle" transform="rotate(-90 {lane + 4} {ly})">MProxyWindow starts</text>')
    s.arrow([(fr.x, fr.mid_y(20)), (main.right, fr.mid_y(20))], "file", label="loads",
            label_at=(fr.x - 8, fr.mid_y(20) - 8), label_anchor="end")


# --- 3. Where things are ---

def where(s, y):
    y = section_title(s, y, "3", "Where things are", "the source tree, the installation, the user's files")
    y += 24
    panels = [
        ("The repository", [
            ("Maia/MaiaServerApp/", "appMaiaServer: main.cpp (server / client mode), logger"),
            ("Maia/BackendLib/", "the server core (server/), Maia.Backend QML types, D-Bus contract (dbus/)"),
            ("Maia/ClientLib/", "MLocaleSettings (part of Maia.Backend)"),
            ("Maia/UILib/", "MControlCenterDialog (older)"),
            ("Maia/FrontendModules/", "the frontend's QML module for the engine (symlink)"),
            ("Maia/Paths/", "~/.config/maia/<v>/ for every component"),
            ("Maia/services/<name>/", "a service: contract/, service/ (Rust), qml/ (module), docs/"),
            ("Maia/frontends/<name>/", "a frontend: qmldir, shell/, theme/, assets/, apps/"),
            ("Maia/LoggerApp/", "appLogger, the live log viewer"),
            ("Maia/DeployFiles/", "sessions, session scripts, etc/ defaults, installer"),
            ("apps/settings/", "maia-settings: src/, qml/ (Maia.SettingsKit), pages/"),
            ("apps/calculator/", "the calculator prototype (Rust backend)"),
            ("3rdparty/capnproto/", "Cap'n Proto, bundled (C++ side of the contracts)"),
            ("cmake/", "MaiaQmlModule, MaiaRust, MaiaCapnProto helpers"),
            ("kwin_decorations/, Experimental/", "decoration and toolkit experiments"),
            ("doc/diagrams/", "this map and the service diagrams (Python → SVG)"),
            ("TODO.md", "known problems and plans"),
        ]),
        ("The installation  <prefix> = /opt/Maia/Maia_<v>", [
            ("bin/appMaiaServer", "the server and the shell"),
            ("bin/maia-settings, bin/appLogger", "Maia Settings, the log viewer"),
            ("bin/run_maia_kwin.sh, run_maia_wayfire.sh", "the session scripts (the environment)"),
            ("bin/maia-session-common.sh", "their common part"),
            ("bin/run_maia_nested_wayland.sh", "Maia in a nested KWin window (development)"),
            ("bin/maia_<v>-kwin.desktop, -wayfire.desktop", "copied to /usr/share/wayland-sessions"),
            ("libexec/maia-session-service", "the main process of a session"),
            ("libexec/maia-*-service", "the services: windows, network, appearance"),
            ("lib/x86_64-linux-gnu/qml6/Maia/", "the QML modules Windows, Network, Appearance, Session"),
            ("frontends/<name>/", "the frontends, as in the repository"),
            ("share/maia-settings/pages/", "the pages of Maia Settings"),
            ("share/aurorae/themes/", "decorations shipped with Maia (Se7enAero, XBoomer)"),
            ("share/applications/", "org.maia.settings.desktop"),
            ("etc/xdg/kded6rc, kwalletrc", "Maia's defaults for KDE (last in XDG_CONFIG_DIRS)"),
            ("etc/maia/session.toml", "what a session runs, in which order, how restarted"),
            ("etc/maia/wayfire.ini", "the template of the Wayfire session's configuration"),
            ("../install_on_ubuntu.sh", "the installer"),
        ]),
        ("The user's files", [
            ("~/.config/maia/<v>/maia.conf", "QSettings: favourites, the frontends' settings"),
            ("~/.config/maia/<v>/maiarc", "KConfig: active frontend, 24-hour clock"),
            ("~/.config/maia/<v>/appearance.json", "maia-appearance-service: decoration per frontend"),
            ("~/.config/maia/<v>/wayfire.ini", "the Wayfire session (made on its first start)"),
            ("", "every Maia version has its own directory; nothing is migrated"),
            ("~/.config/kwinrc, kdeglobals, kxkbrc", "KDE's files Maia reads or writes"),
            ("~/.local/share/aurorae/themes/", "decorations the user installed"),
            ("~/maia_<v>_server.log", "the log of appMaiaServer"),
            ("~/maia_<v>_kwin_session.log", "the session: every process, line by line (or _wayfire_)"),
            ("$XDG_RUNTIME_DIR/maia/*.sock", "the sockets of the services (per display / session)"),
            ("$XDG_RUNTIME_DIR/maia/qml-modules-<pid>/", "the frontends' module symlinks"),
            ("$XDG_RUNTIME_DIR/maia-nested-wayland.env", "connection data of a nested session"),
        ]),
    ]
    widths = [1300, 1140, 1060]
    x = 40
    heights = []
    for (title, items), w in zip(panels, widths):
        h = 60 + 20 * len(items) + 14
        heights.append(h)
    h = max(heights)
    for (title, items), w in zip(panels, widths):
        s.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5"/>')
        s.text(x + 20, y + 32, title, size=16, weight="bold")
        cy = y + 62
        path_w = max(len(p) for p, _ in items) * 6.6 + 30
        for path, text in items:
            if path:
                s.text(x + 20, cy, path, size=11.5, fill="#7c2d12", mono=True)
                s.text(x + 20 + path_w, cy, text, size=12.5, fill="#1e293b")
            else:
                s.text(x + 20 + path_w, cy, text, size=12.5, fill="#475569", italic=True)
            cy += 20
        x += w + 30
    return y + h


def main():
    s = Svg(W)
    header(s)
    y = session_start(s, 370)
    y = running_session(s, y + 50)
    y = where(s, y + 10)
    out = os.path.join(os.getcwd(), "maia-project-map.svg")
    with open(out, "w", encoding="utf-8") as f:
        f.write(s.render(y + 40))
    print(out)


if __name__ == "__main__":
    main()
