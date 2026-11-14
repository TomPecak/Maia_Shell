#!/usr/bin/env python3
"""A pretend copy, reported the way KIO reports one for Dolphin (KJobWidgets' KUiServerV2JobTracker):
org.kde.JobViewServerV2.requestView, then org.kde.JobViewV3.update a few times a second and
terminate. Pause and cancel from the shell work. Nothing is copied.

    fake-job.py                      # 10 s, 1 GiB, as Dolphin
    fake-job.py --seconds 30 --size 15000 --fail
"""

import argparse
import sys

from gi.repository import Gio, GLib

KILLABLE, SUSPENDABLE = 1, 2
TICK_MS = 100


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--seconds", type=float, default=10, help="how long the copy takes")
    parser.add_argument("--size", type=int, default=1024, help="MiB to copy")
    parser.add_argument("--app", default="org.kde.dolphin", help="desktop entry of the application")
    parser.add_argument("--title", default="Copying")
    parser.add_argument("--dest", default="file:///media/usb", help="where it writes to")
    parser.add_argument("--fail", action="store_true", help="end with an error halfway")
    args = parser.parse_args()

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    hints = {"title": GLib.Variant("s", args.title)}
    try:
        reply = bus.call_sync("org.kde.JobViewServer", "/JobViewServer", "org.kde.JobViewServerV2", "requestView",
                              GLib.Variant("(sia{sv})", (args.app, KILLABLE | SUSPENDABLE, hints)),
                              GLib.VariantType("(o)"), Gio.DBusCallFlags.NONE, 5000)
    except GLib.Error as error:
        sys.exit(f"no job server: {error.message}")
    path = reply.unpack()[0]
    print(f"job {path}")

    total = args.size * 1024 * 1024
    ticks = max(1, int(args.seconds * 1000 / TICK_MS))
    state = {"tick": 0, "paused": False}
    loop = GLib.MainLoop()

    def call(method, signature, values):
        bus.call_sync("org.kde.JobViewServer", path, "org.kde.JobViewV3", method,
                      GLib.Variant(signature, values), None, Gio.DBusCallFlags.NONE, 5000)

    def terminate(code, message):
        call("terminate", "(usa{sv})", (code, message, {}))
        loop.quit()

    def on_signal(_bus, _sender, _path, _iface, member, _params, _data):
        print(member)
        if member == "cancelRequested":
            terminate(1, "")  # KIO::ERR_USER_CANCELED
        elif member in ("suspendRequested", "resumeRequested"):
            state["paused"] = member == "suspendRequested"
            call("update", "(a{sv})", ({"suspended": GLib.Variant("b", state["paused"])},))

    bus.signal_subscribe(None, "org.kde.JobViewV3", None, path, None, Gio.DBusSignalFlags.NONE, on_signal, None)

    def tick():
        if state["paused"]:
            return True
        state["tick"] += 1
        done = total * state["tick"] // ticks
        if args.fail and state["tick"] >= ticks // 2:
            terminate(2, "The device is not writable")
            return False
        call("update", "(a{sv})", ({
            "infoMessage": GLib.Variant("s", f"{args.title} film.mkv"),
            "percent": GLib.Variant("u", 100 * state["tick"] // ticks),
            "processedBytes": GLib.Variant("t", done),
            "totalBytes": GLib.Variant("t", total),
            "totalFiles": GLib.Variant("t", 1),
            "speed": GLib.Variant("t", total * 1000 // ticks // TICK_MS),
            "descriptionLabel1": GLib.Variant("s", "Source"),
            "descriptionValue1": GLib.Variant("s", "~/film.mkv"),
            "destUrl": GLib.Variant("s", args.dest),
        },))
        if state["tick"] >= ticks:
            terminate(0, "")
            return False
        return True

    GLib.timeout_add(TICK_MS, tick)
    loop.run()


if __name__ == "__main__":
    main()
