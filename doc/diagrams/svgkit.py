"""Small SVG drawing kit for the Maia architecture diagrams (doc/diagrams/service_diagrams.py).

The diagrams share one visual language, explained by the legend each of them carries:

- processes are thick rounded frames with a coloured title bar (Maia services violet, system
  processes teal, Maia clients blue);
- inside them: modules and classes as white cards with a kind tag (Rust module, C++ class,
  QML type) and the file or folder in the repository;
- files on disk have a folded corner, buses (D-Bus, Wayland, sockets) are pills;
- arrows are coloured by the kind of connection and routed through the gutters between the
  columns, so they never cross a card.
"""

from xml.sax.saxutils import escape

FONT = "Noto Sans, DejaVu Sans, Liberation Sans, sans-serif"
MONO = "DejaVu Sans Mono, Liberation Mono, monospace"

# --- Colours ---

PROCESS_MAIA = "#7c3aed"      # Maia's own services
PROCESS_SYSTEM = "#0f766e"    # system processes (KWin, NetworkManager, ...)
PROCESS_CLIENT = "#0284c7"    # Maia shells and apps using the service
PROCESS_CHILD = "#64748b"     # short-lived child processes

KIND = {
    "rust": ("Rust module", "#c2410c"),
    "cpp": ("C++ class", "#1d4ed8"),
    "qml": ("QML type", "#047857"),
    "contract": ("Cap'n Proto schema", "#7c3aed"),
    "system": ("system component", "#0f766e"),
    "config": ("config", "#9a3412"),
    "shell": ("QML shell part", "#0369a1"),
}

ARROW = {
    "call": ("#334155", False, "call inside a process"),
    "capnp": ("#7c3aed", False, "Cap'n Proto RPC (Unix socket)"),
    "dbus": ("#2563eb", False, "D-Bus"),
    "wayland": ("#16a34a", False, "Wayland protocol"),
    "file": ("#ea580c", False, "reads / writes a file"),
    "spawn": ("#64748b", True, "starts a process"),
    "import": ("#0284c7", True, "QML import (module loaded into the process)"),
}


class Rect:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h

    @property
    def right(self):
        return self.x + self.w

    @property
    def bottom(self):
        return self.y + self.h

    def mid_y(self, offset=0):
        return self.y + self.h / 2 + offset

    def mid_x(self, offset=0):
        return self.x + self.w / 2 + offset


class Svg:
    def __init__(self, width):
        self.width = width
        self.parts = []

    # --- Primitives ---

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=13, weight="normal", fill="#0f172a", anchor="start", mono=False, italic=False):
        family = MONO if mono else FONT
        style = ' font-style="italic"' if italic else ""
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{fill}" text-anchor="{anchor}"{style}>{escape(s)}</text>')

    def tag(self, right_x, y, label, color, filled=True):
        w = 10 + len(label) * 6.2
        x = right_x - w
        if filled:
            self.add(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="17" rx="8.5" fill="{color}"/>')
            self.text(x + w / 2, y + 12.5, label, size=10.5, weight="bold", fill="#ffffff", anchor="middle")
        else:
            self.add(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="17" rx="8.5" fill="#ffffff" stroke="{color}" stroke-width="1.4"/>')
            self.text(x + w / 2, y + 12.5, label, size=10.5, weight="bold", fill=color, anchor="middle")
        return w

    # --- Containers ---

    def column_title(self, x, y, w, title, subtitle):
        self.text(x, y, title, size=17, weight="bold")
        self.text(x, y + 19, subtitle, size=12, fill="#475569")
        self.add(f'<line x1="{x}" y1="{y + 28}" x2="{x + w}" y2="{y + 28}" stroke="#cbd5e1" stroke-width="1.5"/>')

    def process(self, rect, title, subtitle, color, path=None):
        r = rect
        self.add(f'<rect x="{r.x}" y="{r.y}" width="{r.w}" height="{r.h}" rx="16" fill="{color}" fill-opacity="0.05" '
                 f'stroke="{color}" stroke-width="3"/>')
        self.add(f'<path d="M{r.x},{r.y + 40} v-24 a16,16 0 0 1 16,-16 h{r.w - 32} a16,16 0 0 1 16,16 v24 z" fill="{color}"/>')
        self.text(r.x + 16, r.y + 26, title, size=16, weight="bold", fill="#ffffff")
        self.text(r.right - 14, r.y + 26, subtitle, size=11.5, fill="#ffffff", anchor="end")
        if path:
            self.text(r.x + 16, r.y + 58, path, size=11, fill="#334155", mono=True)

    def library(self, rect, title, subtitle, path=None, color="#047857"):
        """A shared library loaded into other processes (a QML module): a dashed frame"""
        r = rect
        self.add(f'<rect x="{r.x}" y="{r.y}" width="{r.w}" height="{r.h}" rx="14" fill="{color}" fill-opacity="0.05" '
                 f'stroke="{color}" stroke-width="2.2" stroke-dasharray="9 5"/>')
        self.text(r.x + 16, r.y + 25, title, size=15, weight="bold", fill=color)
        self.text(r.right - 14, r.y + 25, subtitle, size=11.5, fill=color, anchor="end")
        if path:
            self.text(r.x + 16, r.y + 44, path, size=11, fill="#334155", mono=True)

    # --- Cards ---

    @staticmethod
    def card_height(lines, path=True):
        return 30 + (16 if path else 0) + 15 * len(lines) + 8

    def card(self, x, y, w, title, kind, lines=(), path=None, accent=None):
        """A module, class or component; returns its Rect"""
        label, color = KIND[kind]
        h = self.card_height(lines, path is not None)
        stroke = accent or "#94a3b8"
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#ffffff" stroke="{stroke}" stroke-width="1.5"/>')
        self.add(f'<rect x="{x}" y="{y}" width="5" height="{h}" rx="2" fill="{color}"/>')
        self.text(x + 14, y + 21, title, size=13.5, weight="bold")
        self.tag(x + w - 8, y + 7, label, color)
        cy = y + 38
        if path:
            self.text(x + 14, cy, path, size=10.5, fill="#64748b", mono=True)
            cy += 16
        for line in lines:
            self.text(x + 14, cy, line, size=11.5, fill="#334155")
            cy += 15
        return Rect(x, y, w, h)

    def file(self, x, y, w, title, lines=(), path_lines=()):
        """A file or directory on disk; returns its Rect"""
        h = 30 + 15 * (len(lines) + len(path_lines)) + 8
        f = 18
        self.add(f'<path d="M{x},{y} h{w - f} l{f},{f} v{h - f} h{-w} z" fill="#fff7ed" stroke="#ea580c" stroke-width="1.8"/>')
        self.add(f'<path d="M{x + w - f},{y} v{f} h{f}" fill="none" stroke="#ea580c" stroke-width="1.8"/>')
        self.text(x + 12, y + 20, title, size=13, weight="bold", fill="#9a3412")
        cy = y + 37
        for line in path_lines:
            self.text(x + 12, cy, line, size=10.5, fill="#7c2d12", mono=True)
            cy += 15
        for line in lines:
            self.text(x + 12, cy, line, size=11.5, fill="#431407")
            cy += 15
        return Rect(x, y, w, h)

    def bus(self, x, y, w, title, lines=(), color="#2563eb"):
        """A bus or socket (D-Bus, Wayland, a Unix socket); returns its Rect"""
        h = 30 + 15 * len(lines) + 6
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h / 2:.1f}" fill="{color}" fill-opacity="0.08" '
                 f'stroke="{color}" stroke-width="2"/>')
        self.text(x + w / 2, y + 20, title, size=13, weight="bold", fill=color, anchor="middle")
        cy = y + 36
        for line in lines:
            self.text(x + w / 2, cy, line, size=11, fill="#1e293b", anchor="middle", mono=line.startswith("$") or "/" in line)
            cy += 15
        return Rect(x, y, w, h)

    # --- Arrows ---

    def markers(self):
        out = []
        for name, (color, _, _) in ARROW.items():
            out.append(f'<marker id="end-{name}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                       f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{color}"/></marker>')
        return "<defs>" + "".join(out) + "</defs>"

    def arrow(self, points, kind, both=False, label=None, label_at=None, label_anchor="start", width=2.2):
        color, dashed, _ = ARROW[kind]
        d = "M" + " L".join(f"{px:.1f},{py:.1f}" for px, py in points)
        dash = ' stroke-dasharray="7 5"' if dashed else ""
        start = f' marker-start="url(#end-{kind})"' if both else ""
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{dash} '
                 f'marker-end="url(#end-{kind})"{start} stroke-linejoin="round"/>')
        if label:
            lx, ly = label_at or points[0]
            for i, part in enumerate(label.split("\n")):
                # A white plate under the label (paint-order halos are not drawn by every renderer)
                tw = 6.3 * len(part) + 6
                tx = lx - 3 if label_anchor == "start" else lx - tw + 3
                self.add(f'<rect x="{tx:.1f}" y="{ly + i * 13 - 10:.1f}" width="{tw:.1f}" height="13" rx="3" '
                         f'fill="#ffffff" fill-opacity="0.92"/>')
                self.add(f'<text x="{lx:.1f}" y="{ly + i * 13:.1f}" font-family="{FONT}" font-size="11" font-weight="bold" '
                         f'fill="{color}" text-anchor="{label_anchor}">{escape(part)}</text>')

    def link(self, a, b, kind, lane_x, a_dy=0, b_dy=0, both=False, label=None, label_dy=-6):
        """From the right edge of a to the left edge of b (or back), through the lane x"""
        if a.right <= b.x:
            ay, by = a.mid_y(a_dy), b.mid_y(b_dy)
            pts = [(a.right, ay), (lane_x, ay), (lane_x, by), (b.x, by)]
        else:
            ay, by = a.mid_y(a_dy), b.mid_y(b_dy)
            pts = [(a.x, ay), (lane_x, ay), (lane_x, by), (b.right, by)]
        self.arrow(pts, kind, both=both, label=label,
                   label_at=((pts[0][0] + 6) if a.right <= b.x else (pts[0][0] - 6), ay + label_dy),
                   label_anchor="start" if a.right <= b.x else "end")

    def down(self, a, b, kind, dx=0, label=None):
        x = a.mid_x(dx)
        self.arrow([(x, a.bottom), (x, b.y)], kind, label=label, label_at=(x + 6, (a.bottom + b.y) / 2 + 4))

    # --- Panels ---

    def panel(self, rect, title):
        r = rect
        self.add(f'<rect x="{r.x}" y="{r.y}" width="{r.w}" height="{r.h}" rx="12" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5"/>')
        self.text(r.x + 18, r.y + 28, title, size=17, weight="bold")

    def api_block(self, x, y, w, name, who, methods):
        """An interface of the contract and its methods; returns the height used. A note that does
        not fit after its signature goes on the next line."""
        self.text(x, y, name, size=14, weight="bold", fill="#5b21b6")
        self.text(x + 8.2 * len(name) + 10, y, who, size=11, fill="#64748b", italic=True)
        cy = y + 18
        for signature, note in methods:
            self.text(x + 8, cy, signature, size=11, fill="#0f172a", mono=True)
            sig_w = 6.7 * len(signature)
            if note and 8 + sig_w + 12 + 6.0 * len(note) <= w:
                self.text(x + 8 + sig_w + 12, cy, note, size=11, fill="#475569")
            elif note:
                cy += 14
                self.text(x + 22, cy, note, size=11, fill="#475569")
            cy += 16
        return cy - y + 10

    def legend(self, x, y):
        """The shared legend; returns the height used"""
        cy = y
        # Shapes
        shapes = [
            ("process", "a process (its own address space)"),
            ("library", "library loaded into other processes (QML module)"),
            ("card", "module or class; the tag says which"),
            ("file", "file or directory on disk"),
            ("bus", "bus or socket"),
        ]
        for shape, text in shapes:
            if shape == "process":
                self.add(f'<rect x="{x}" y="{cy}" width="42" height="22" rx="7" fill="{PROCESS_MAIA}" fill-opacity="0.05" stroke="{PROCESS_MAIA}" stroke-width="3"/>')
            elif shape == "library":
                self.add(f'<rect x="{x}" y="{cy}" width="42" height="22" rx="7" fill="#047857" fill-opacity="0.05" stroke="#047857" stroke-width="2" stroke-dasharray="6 4"/>')
            elif shape == "card":
                self.add(f'<rect x="{x}" y="{cy}" width="42" height="22" rx="5" fill="#ffffff" stroke="#94a3b8" stroke-width="1.5"/>')
                self.add(f'<rect x="{x}" y="{cy}" width="5" height="22" rx="2" fill="#c2410c"/>')
            elif shape == "file":
                self.add(f'<path d="M{x},{cy} h30 l12,12 v10 h-42 z" fill="#fff7ed" stroke="#ea580c" stroke-width="1.8"/>')
            else:
                self.add(f'<rect x="{x}" y="{cy}" width="42" height="22" rx="11" fill="#2563eb" fill-opacity="0.08" stroke="#2563eb" stroke-width="2"/>')
            self.text(x + 54, cy + 16, text, size=12)
            cy += 30
        # Process colours
        for color, text in [(PROCESS_MAIA, "Maia service"), (PROCESS_SYSTEM, "system process"),
                            (PROCESS_CLIENT, "Maia shell or app (client)"), (PROCESS_CHILD, "child process")]:
            self.add(f'<rect x="{x}" y="{cy + 3}" width="42" height="14" rx="4" fill="{color}"/>')
            self.text(x + 54, cy + 15, text, size=12)
            cy += 22
        cy += 6
        # Kind tags
        tx = x
        for key in ["rust", "cpp", "qml", "contract", "system", "config", "shell"]:
            label, color = KIND[key]
            w = 10 + len(label) * 6.2
            if tx + w > x + 400:
                tx = x
                cy += 24
            self.tag(tx + w, cy, label, color)
            tx += w + 8
        cy += 34
        # Arrows
        for kind, (color, dashed, text) in ARROW.items():
            self.arrow([(x, cy + 6), (x + 42, cy + 6)], kind)
            self.text(x + 54, cy + 10, text, size=12)
            cy += 22
        return cy - y

    def render(self, height):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" height="{height:.0f}" '
                f'viewBox="0 0 {self.width} {height:.0f}">')
        return "\n".join([head, self.markers(), f'<rect width="{self.width}" height="{height:.0f}" fill="#ffffff"/>']
                         + self.parts + ["</svg>"])
