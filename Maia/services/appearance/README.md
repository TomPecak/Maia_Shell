# Maia appearance service

How a Maia session looks, in one place: **window decorations** now, icons, cursors and colors
later. The service is the only part of Maia that knows how the compositor stores its look (KWin:
`kwinrc`, its D-Bus); shells, Maia Settings and apps use the contract through the QML module
`Maia.Appearance` and never write `kwinrc` themselves.

```
 Lumen, XPLuna, ...           Maia Settings                  apps
   FrontendLook                 WindowDecorations
        └──────────── Maia.Appearance (QML module, C++) ───────────┘
                               │ Cap'n Proto, $XDG_RUNTIME_DIR/maia/appearance-$WAYLAND_DISPLAY.sock
                  maia-appearance-service (Rust)
                    rpc/ ── decorations/ (catalog, choice, install, per-frontend memory)
                                 │
                    compositor/ kwin.rs ── kwinrc (kwriteconfig6) + D-Bus reloadConfig,
                                           checked with supportInformation
                                fake.rs (tests)      later: wayfire.rs
```

| Path | What |
|---|---|
| `contract/appearance.capnp` | The service: `info()`, `decorations()`; one interface per area |
| `contract/decorations.capnp` | Window decorations: themes, choice, install, frontends. Read it first. |
| `contract/common.capnp` | Result, ErrorCode, Subscription |
| `service/src/lib.rs` | Map of the Rust code (start here) |
| `service/src/compositor/` | One backend per compositor (`kwin.rs`, `fake.rs`) behind the `Compositor` trait |
| `service/src/decorations/` | The decorations area, without Cap'n Proto |
| `service/src/rpc/` | The Cap'n Proto side |
| `service/tests/service.rs` | The service over a real connection with the fake compositor |
| `service/examples/list.rs` | Prints what a running service serves (read-only) |
| `qml/` | `Maia.Appearance`: `WindowDecorations` (model + commands), `FrontendLook`, `Appearance` enums |
| `docs/adding-an-area.md`, `docs/adding-a-compositor.md` | How to extend it |

## Themes

A theme is named `<engine>:<name>` on every compositor:

| Engine | What | KWin (`kwinrc [org.kde.kdecoration2]`) |
|---|---|---|
| `aurorae-svg` | `aurorae/themes/<name>/` with `metadata.desktop`, `decoration.svg` | `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__<name>` |
| `aurorae-qml` | `kwin/decorations/<id>/` (KPackage) | `library=org.kde.kwin.aurorae`, `theme=<id>` |
| `kdecoration` | `qt6/plugins/org.kde.kdecoration3/<id>.so` (Breeze, Oxygen) | `library=<id>` |
| `wayfire` | Wayfire's own (later) | - |

They are found in every XDG data directory, the user's first; Maia's own `<prefix>/share` is in
`XDG_DATA_DIRS` of a Maia session, so frontends install their themes there (XPLuna:
`share/aurorae/themes/XBoomer`) instead of copying them into the user's home. Names of native
plugins come from the plugin files (Qt metadata), in the user's language.

**Installing** (`install(path)`): an Aurorae SVG theme from a directory or an archive (tar.gz/xz/
zst/bz2, zip), into `~/.local/share/aurorae/themes`. The archive's listing is checked before it is
unpacked (files and directories only, no paths leaving it, at most 2000 entries and 64 MB), the
unpacked tree again, then the theme is moved into place with one rename. QML themes are refused:
they are code running inside the compositor. Only the user's themes can be removed, not the one in
use.

**Frontends**: a frontend declares its look in its shell, `FrontendLook { frontend: "XPLuna";
windowDecoration: "aurorae-svg:XBoomer" }`. The first time, its default is used (an empty default
keeps what is chosen); what the user chooses while the frontend runs, here or in KDE's settings, is
remembered for that frontend (`~/.config/maia/<Maia version>/appearance.json`) and used next time instead.

**Changing**: `set()` writes kwinrc, tells KWin and waits until KWin reports the new decoration
(KWin falls back to Breeze when a plugin fails: that is a `failed` result with what it uses
instead). Changes made by other programs (KDE's System Settings) are noticed through inotify.

## Running and testing

Started by the session scripts (`Maia/DeployFiles/session/maia-session-common.sh.in`, only in the
KWin session until there is a Wayfire backend; `run_maia_nested_wayland.sh`).

| Variable | Meaning |
|---|---|
| `MAIA_APPEARANCE_SOCKET` | Socket path (service and clients) |
| `MAIA_APPEARANCE_BACKEND` | `kwin` (default) or `fake` (in memory, nothing is changed) |
| `MAIA_KWRITECONFIG` | Program used to write kwinrc (default `kwriteconfig6`) |
| `MAIA_APPEARANCE_PLUGIN_DIRS` | Qt plugin directories to search instead of the usual ones (tests) |
| `MAIA_APPEARANCE_MAIA_DATA_DIRS` | Data directories whose themes count as Maia's |

```bash
cd service && cargo test                    # unit tests, the RPC test (fake compositor, temp dirs)
ctest --test-dir <build> -R maia-appearance # cargo test and the QML model test
cargo run --example list -- <socket>        # what a running service serves
```

The `kwin` backend writes the `kwinrc` of `$XDG_CONFIG_HOME`: test it in a nested session with an
isolated `XDG_CONFIG_HOME`, or use `fake`.
