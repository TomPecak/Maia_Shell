#!/usr/bin/env python3
"""An old X11 tray icon (XEmbed, GTK 3's Gtk.StatusIcon through Xwayland), as Wine, old GTK 2 and
Java programs have one. It reaches the tray only through KDE's xembedsniproxy, which turns it into
an item. A left click and a right click print what arrived; the right click opens GTK's own menu.

    xembed-tray-icon.py
"""

import os
import sys

os.environ["GDK_BACKEND"] = "x11"
import gi  # noqa: E402

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

if not os.environ.get("DISPLAY"):
    sys.exit("no DISPLAY: XEmbed icons need Xwayland")

icon = Gtk.StatusIcon.new_from_icon_name("face-smile")
icon.set_tooltip_text("XEmbed tray test")
icon.set_title("XEmbed tray test")

menu = Gtk.Menu()
for label in ("First", "Second"):
    item = Gtk.MenuItem(label=label)
    item.connect("activate", lambda _, l=label: print(f"menu {l}", flush=True))
    menu.append(item)
quit_item = Gtk.MenuItem(label="Quit")
quit_item.connect("activate", lambda _: Gtk.main_quit())
menu.append(quit_item)
menu.show_all()

icon.connect("activate", lambda _: print("left click", flush=True))
icon.connect("popup-menu", lambda _, button, time: (print("right click", flush=True),
                                                   menu.popup(None, None, None, None, button, time)))
print("XEmbed icon shown", flush=True)
Gtk.main()
