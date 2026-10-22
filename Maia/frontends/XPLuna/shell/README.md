# XPLuna shell

`Main.qml` is the entry point: the fullscreen desktop window that puts the parts below together.
Each directory is one part of the GUI, with its windows, contents and popups:

| Directory     | What is there                                                                 |
|---------------|-------------------------------------------------------------------------------|
| `desktop/`    | wallpaper with its context menu, sticky notes, the "Maia Shell" label         |
| `taskbar/`    | bottom panel: start button, task buttons, notification area and clock         |
| `startmenu/`  | start menu (apps list, log off / turn off buttons)                            |
| `volume/`     | volume slider opened from the notification area                               |
| `session/`    | "Log off Windows" and "Turn off computer" dialogs                             |
| `experiments/`| unused experiments kept for reference (3D clock, overlay mask window)         |

`*Window.qml` / `*Dialog.qml` is the top-level window, `*Content.qml` what is drawn inside it, `*Popup.qml`
an alternative implementation as a Qt Quick popup. Shared styled controls (XPMenu, TiledImage) and the
assets live in the frontend root (module `XPLunaFrontend`), imported by name.
