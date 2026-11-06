# Adding a compositor (Wayfire)

A compositor is a backend in `service/src/compositor/`, implementing the `Compositor` trait
(`mod.rs`): what it draws (`info().engines`), what its settings say (`read`), using a theme
(`apply_theme`, answering only once the compositor took it, or with what it uses instead), the
border size, and watching its settings for changes by other programs.

For Wayfire (`wayfire.rs`):

- **Engines**: `AuroraeSvg` (the wayfire-aurorae plugin), `Wayfire` (its own `decoration`
  plugin). Not `Kdecoration` / `AuroraeQml`: those themes are listed with available = false.
- **Settings**: `~/.config/wayfire.ini`: the plugin list (`[core] plugins`, the aurorae plugin
  instead of `decoration`) and the plugin's section with the theme's name. Wayfire re-reads the
  file when it changes. Keep the rest of the file as it is (edit lines, write atomically).
- **Checking**: Wayfire's IPC (JSON over `$WAYFIRE_SOCKET`, the ipc plugin) to read the option
  back.
- **Choosing the backend**: in `compositor::create()` / main.rs, from `MAIA_APPEARANCE_BACKEND`
  or the running compositor (`$WAYFIRE_SOCKET` set, `XDG_CURRENT_DESKTOP`).

The theme ids stay the same (`aurorae-svg:XBoomer`), so the frontends' remembered choices work on
both compositors.
