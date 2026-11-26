#!/usr/bin/env python3
"""A pretend application with a tray icon, as KStatusNotifierItem shows one: an
org.kde.StatusNotifierItem with a com.canonical.dbusmenu menu, registered with the watcher
(org.kde.StatusNotifierWatcher). What the tray does with it is printed, one line each:

    Activate 10 20        Token <token>        Event 3 clicked        AboutToShow 0

Commands on stdin change it, each followed by the item's signal:

    status Passive|Active|NeedsAttention    title <text>    icon <name>    pixmap <rrggbb>
    tooltip <text>    menu <entries>    quit

The menu (--menu, the command menu): entries separated by "," — "-" a separator, "Label>A|B|C" a
submenu, "[x]Label" / "[ ]Label" a check box, "(o)Label" / "( )Label" a radio button (one of the
entries between two separators), "!Label" disabled. A click on a check box or radio button changes
it, as an application would, and the menu changes (LayoutUpdated).

    fake-tray-item.py                                  # "Fake chat", an icon of the theme
    fake-tray-item.py --title Music --icon media-playback-start --status Passive
    fake-tray-item.py --pixmap ff8800 --attention-after 5
    fake-tray-item.py --menu "Show,-,Status>(o)Online|( )Away|( )Busy,[x]Sounds,!Offline mode,-,Quit"
"""

import argparse
import os
import sys
import warnings

from gi.repository import Gio, GLib

# Gio's register_object with callbacks is the simplest way to serve an object from Python
warnings.filterwarnings("ignore", category=DeprecationWarning)

ITEM_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
    <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
    <method name="ProvideXdgActivationToken"><arg name="token" type="s" direction="in"/></method>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewAttentionIcon"/>
    <signal name="NewOverlayIcon"/>
    <signal name="NewToolTip"/>
    <signal name="NewStatus"><arg name="status" type="s"/></signal>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <method name="GetLayout">
      <arg name="parentId" type="i" direction="in"/><arg name="recursionDepth" type="i" direction="in"/>
      <arg name="propertyNames" type="as" direction="in"/>
      <arg name="revision" type="u" direction="out"/><arg name="layout" type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg name="ids" type="ai" direction="in"/><arg name="propertyNames" type="as" direction="in"/>
      <arg name="properties" type="a(ia{sv})" direction="out"/>
    </method>
    <method name="Event">
      <arg name="id" type="i" direction="in"/><arg name="eventId" type="s" direction="in"/>
      <arg name="data" type="v" direction="in"/><arg name="timestamp" type="u" direction="in"/>
    </method>
    <method name="AboutToShow">
      <arg name="id" type="i" direction="in"/><arg name="needUpdate" type="b" direction="out"/>
    </method>
    <signal name="LayoutUpdated"><arg name="revision" type="u"/><arg name="parent" type="i"/></signal>
  </interface>
</node>
"""


def parse_menu(text):
    """The entries of --menu, with ids in their order (depth first)"""
    next_id = [1]

    def entry(spec, children=()):
        spec = spec.strip()
        e = {"id": next_id[0], "separator": spec == "-", "label": "", "enabled": True,
             "toggle": "", "checked": False, "children": []}
        next_id[0] += 1
        if spec.startswith("!"):
            e["enabled"], spec = False, spec[1:]
        for mark, toggle, checked in (("[x]", "checkmark", True), ("[ ]", "checkmark", False),
                                      ("(o)", "radio", True), ("( )", "radio", False)):
            if spec.startswith(mark):
                e["toggle"], e["checked"], spec = toggle, checked, spec[len(mark):]
        e["label"] = spec
        e["children"] = [entry(c) for c in children]
        return e

    entries = []
    for part in [p for p in text.split(",") if p.strip()] if text else []:
        label, _, children = part.partition(">")
        entries.append(entry(label, [c for c in children.split("|") if c.strip()] if children else ()))
    return entries


def say(line):
    print(line, flush=True)


def square(color, side):
    """An opaque square, ARGB32 in network byte order"""
    r, g, b = (int(color[i:i + 2], 16) for i in (0, 2, 4))
    return (side, side, bytes([255, r, g, b]) * (side * side))


class Item:
    def __init__(self, args, bus):
        self.bus = bus
        self.path = "/StatusNotifierItem"
        self.title = args.title
        self.status = args.status
        self.icon = args.icon
        self.pixmaps = [square(args.pixmap, 22), square(args.pixmap, 44)] if args.pixmap else []
        self.tooltip = args.tooltip
        self.item_is_menu = args.item_is_menu
        self.entries = parse_menu(args.menu)
        self.revision = 1

    def properties(self):
        empty = GLib.Variant("a(iiay)", [])
        return {
            "Category": GLib.Variant("s", "Communications"),
            "Id": GLib.Variant("s", "fake-tray-item"),
            "Title": GLib.Variant("s", self.title),
            "Status": GLib.Variant("s", self.status),
            "WindowId": GLib.Variant("i", 0),
            "IconName": GLib.Variant("s", self.icon),
            "IconPixmap": GLib.Variant("a(iiay)", self.pixmaps),
            "AttentionIconName": GLib.Variant("s", "mail-unread-new"),
            "AttentionIconPixmap": empty,
            "OverlayIconName": GLib.Variant("s", ""),
            "OverlayIconPixmap": empty,
            "IconThemePath": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], self.title, self.tooltip)),
            "ItemIsMenu": GLib.Variant("b", self.item_is_menu),
            "Menu": GLib.Variant("o", "/MenuBar" if self.entries else "/NO_DBUSMENU"),
        }

    def get_property(self, connection, sender, path, interface, name):
        return self.properties().get(name)

    def call(self, connection, sender, path, interface, method, params, invocation):
        values = params.unpack()
        if method == "ProvideXdgActivationToken":
            say(f"Token {values[0]}")
        else:
            say(" ".join([method] + [str(v) for v in values]))
        invocation.return_value(None)

    def signal(self, name, value=None):
        self.bus.emit_signal(None, self.path, "org.kde.StatusNotifierItem", name, value)

    # --- The menu ---

    def layout(self):
        def node(entry):
            props = {}
            if entry["separator"]:
                props["type"] = GLib.Variant("s", "separator")
            else:
                props["label"] = GLib.Variant("s", entry["label"])
                if not entry["enabled"]:
                    props["enabled"] = GLib.Variant("b", False)
                if entry["toggle"]:
                    props["toggle-type"] = GLib.Variant("s", entry["toggle"])
                    props["toggle-state"] = GLib.Variant("i", 1 if entry["checked"] else 0)
                if entry["children"]:
                    props["children-display"] = GLib.Variant("s", "submenu")
            return GLib.Variant("(ia{sv}av)", (entry["id"], props, [node(c) for c in entry["children"]]))
        return (0, {"children-display": GLib.Variant("s", "submenu")}, [node(e) for e in self.entries])

    def clicked(self, entry_id):
        """A check box changes, a radio button takes its group"""
        def find(entries):
            for i, entry in enumerate(entries):
                if entry["id"] == entry_id:
                    return entries, i
                found = find(entry["children"])
                if found:
                    return found
            return None
        found = find(self.entries)
        if not found:
            return
        siblings, i = found
        entry = siblings[i]
        if entry["toggle"] == "checkmark":
            entry["checked"] = not entry["checked"]
        elif entry["toggle"] == "radio":
            start = i
            while start > 0 and not siblings[start - 1]["separator"]:
                start -= 1
            end = i
            while end + 1 < len(siblings) and not siblings[end + 1]["separator"]:
                end += 1
            for other in siblings[start:end + 1]:
                if other["toggle"] == "radio":
                    other["checked"] = other is entry
        else:
            return
        self.menu_changed()

    def menu_property(self, connection, sender, path, interface, name):
        return {"Version": GLib.Variant("u", 3), "TextDirection": GLib.Variant("s", "ltr"),
                "Status": GLib.Variant("s", "normal")}.get(name)

    def menu_call(self, connection, sender, path, interface, method, params, invocation):
        values = params.unpack()
        if method == "GetLayout":
            say(f"GetLayout {values[0]}")
            invocation.return_value(GLib.Variant("(u(ia{sv}av))", (self.revision, self.layout())))
        elif method == "AboutToShow":
            say(f"AboutToShow {values[0]}")
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "Event":
            say(f"Event {values[0]} {values[1]}")
            invocation.return_value(None)
            if values[1] == "clicked":
                self.clicked(values[0])
        elif method == "GetGroupProperties":
            invocation.return_value(GLib.Variant("(a(ia{sv}))", ([],)))
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def menu_changed(self):
        self.revision += 1
        self.bus.emit_signal(None, "/MenuBar", "com.canonical.dbusmenu", "LayoutUpdated",
                             GLib.Variant("(ui)", (self.revision, 0)))

    # --- Commands ---

    def command(self, line):
        word, _, rest = line.strip().partition(" ")
        if word == "quit":
            loop.quit()
        elif word == "status":
            self.status = rest
            self.signal("NewStatus", GLib.Variant("(s)", (rest,)))
        elif word == "title":
            self.title = rest
            self.signal("NewTitle")
        elif word == "icon":
            self.icon = rest
            self.signal("NewIcon")
        elif word == "pixmap":
            self.pixmaps = [square(rest, 22), square(rest, 44)]
            self.signal("NewIcon")
        elif word == "tooltip":
            self.tooltip = rest
            self.signal("NewToolTip")
        elif word == "menu":
            self.entries = parse_menu(rest)
            self.menu_changed()
        elif word:
            say(f"unknown command {word}")


def main():
    global loop
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--title", default="Fake chat")
    parser.add_argument("--icon", default="internet-chat", help="an icon name of the theme")
    parser.add_argument("--pixmap", default="", help="an icon as pixels instead: a colour rrggbb")
    parser.add_argument("--status", default="Active", choices=["Passive", "Active", "NeedsAttention"])
    parser.add_argument("--tooltip", default="2 new messages")
    parser.add_argument("--menu", default="Show,-,Quit", help="the menu (see above), '' none")
    parser.add_argument("--item-is-menu", action="store_true", help="a click opens the menu")
    parser.add_argument("--attention-after", type=float, default=0, help="seconds until it needs attention")
    args = parser.parse_args()
    if args.pixmap:
        args.icon = ""

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    item = Item(args, bus)
    bus.register_object(item.path, Gio.DBusNodeInfo.new_for_xml(ITEM_XML).interfaces[0], item.call, item.get_property, None)
    bus.register_object("/MenuBar", Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0], item.menu_call, item.menu_property, None)
    name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
    Gio.bus_own_name_on_connection(bus, name, Gio.BusNameOwnerFlags.NONE, None, None)

    def register():
        try:
            bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                          "RegisterStatusNotifierItem", GLib.Variant("(s)", (name,)), None, Gio.DBusCallFlags.NONE, 5000)
            say(f"registered {name}")
        except GLib.Error as error:
            say(f"no watcher: {error.message}")

    # As KStatusNotifierItem: registered when the watcher is there, again when it comes back
    Gio.bus_watch_name_on_connection(bus, "org.kde.StatusNotifierWatcher", Gio.BusNameWatcherFlags.NONE,
                                     lambda *a: register(), None)

    if args.attention_after > 0:
        GLib.timeout_add(int(args.attention_after * 1000), lambda: item.command("status NeedsAttention") or False)

    def read_stdin(channel, condition):
        line = channel.readline()
        if not line:
            loop.quit()
            return False
        item.command(line)
        return True

    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()), GLib.IO_IN | GLib.IO_HUP, read_stdin)
    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
