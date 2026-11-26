#!/usr/bin/env python3
"""A real Qt application with a tray icon (QSystemTrayIcon with a QMenu, PyQt6), as most KDE and Qt
programs have one: Qt registers it with the watcher only when a host is there, and exports the
menu itself (com.canonical.dbusmenu). A click on the icon shows or hides the window; "Show window"
in the menu raises it (Wayland: with the tray's activation token).

    qt-tray-icon.py
"""

import sys

from PyQt6.QtGui import QAction, QActionGroup, QColor, QIcon, QPixmap
from PyQt6.QtWidgets import QApplication, QLabel, QMenu, QSystemTrayIcon

app = QApplication(sys.argv)
app.setApplicationName("Qt tray test")
app.setDesktopFileName("qt-tray-test")
app.setQuitOnLastWindowClosed(False)

window = QLabel("A window of the Qt tray test.\nThe tray icon shows and hides it.")
window.setMargin(40)
window.setWindowTitle("Qt tray test")

if not QSystemTrayIcon.isSystemTrayAvailable():
    print("no system tray: no StatusNotifierWatcher with a host on the bus", flush=True)

image = QIcon.fromTheme("applications-science")
if image.isNull():
    # No such icon in the theme: a green square, sent to the tray as pixels
    pixmap = QPixmap(64, 64)
    pixmap.fill(QColor("#2e9e5b"))
    image = QIcon(pixmap)
icon = QSystemTrayIcon(image)
icon.setToolTip("Qt tray test")

menu = QMenu()
show = menu.addAction("Show window")
show.triggered.connect(lambda: (window.show(), window.raise_(), window.activateWindow()))
status = menu.addMenu("Status")
group = QActionGroup(status)
for name in ("Online", "Away", "Busy"):
    action = status.addAction(name)
    action.setCheckable(True)
    action.setChecked(name == "Online")
    group.addAction(action)
    action.triggered.connect(lambda checked, n=name: print(f"status {n}", flush=True))
sounds = menu.addAction("Sounds")
sounds.setCheckable(True)
sounds.setChecked(True)
sounds.toggled.connect(lambda on: print(f"sounds {on}", flush=True))
menu.addSeparator()
menu.addAction(QAction("Quit", menu, triggered=app.quit))
icon.setContextMenu(menu)


def activated(reason):
    print(f"activated {reason.name}", flush=True)
    if reason == QSystemTrayIcon.ActivationReason.Trigger:
        window.setVisible(not window.isVisible())


icon.activated.connect(activated)
icon.show()
print("tray icon shown", flush=True)
sys.exit(app.exec())
