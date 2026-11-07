# Maia Settings

`maia-settings [--page <id>]`: the settings of Maia. Lumen's "More Wi-Fi settings" opens it with
`--page network`; a second start hands its page to the running window and exits, so there is
one window per session.

## Not a monolith

| Part | What it is |
|---|---|
| `src/`, `qml/` | The frame: navigation with search, breadcrumb, sub-pages, dialogs, messages, and the components pages build on (QML module `Maia.SettingsKit`, compiled into the program). |
| `pages/<id>/` | One page: `metadata.json` and its QML files, loaded from disk at run time. Installed to `<datadir>/maia-settings/pages/<id>/`. |
| `Maia/services/<service>/qml` | The QML module of a service (`Maia.Network`), installed once and used by the pages, the shells and the apps. |

A page knows its service only through that service's QML module, and the frame only through
`metadata.json`: a new page (Bluetooth, Display, ...) is a new directory, also from another package.

```json
{ "id": "network", "name": "Wi-Fi", "description": "...", "description[pl]": "...",
  "icon": "network-wireless-signal-excellent-symbolic", "order": 10, "main": "WifiPage.qml",
  "formFactors": ["desktop"], "keywords": ["wifi", ...], "keywords[pl]": ["sieć", ...] }
```

What a page can ask of the frame is `SettingsApp` (`qml/SettingsApp.qml`): `push(url, properties)`,
`pop()`, `toast(text, actionText, onAction, onDismissed)`. A page is a `SettingsPage` with a `title`.

Pages are searched in `$MAIA_SETTINGS_PAGES_PATH` (colon separated, for development: point it at
`apps/settings/pages` to run the pages from the sources), the XDG data directories and the
installation's own directory, the first one winning for an id.

## The look

This is the desktop face (docs: memory "faces model"): it uses the Lumen frontend's theme and
components (`import LumenFrontend`), found like the shell finds them (`$MAIA_FRONTENDS_PATH` or
`<prefix>/frontends`, `$MAIA_SETTINGS_FRONTEND` = `Lumen`). The program runs as the shell's
application (`Maia/Maia_<version>`), so it reads the same light/dark and accent settings.

Layout after Windows 11 Settings: navigation at the left (300 px), the page at most 1000 px wide,
cards grouped with 4 px between them, the breadcrumb as title ("Wi-Fi › Saved networks"),
messages inside the page (info bars) where they concern, a toast with "Undo" instead of
confirmation questions for what can be undone, confirmation only for what cannot (forget a network
from its details page, turn off the hotspot).

## The Wi-Fi page

`pages/network/`, after `Maia/services/network/docs/gnome-wifi-features.md`:

| File | Shows |
|---|---|
| `WifiPage.qml`, `DeviceSection.qml`, `NetworkRow.qml` | Switch and state, failures and captive portal, saved networks, hidden network, hotspot, networks in reach (scanned every 15 s while shown), several adapters with a selector |
| `SavedNetworksPage.qml` | Saved networks, the last used first; share, details, forget with undo |
| `NetworkDetailsPage.qml` | Details (signal, speed, band, addresses, DNS, last used), automatic connection, all users, metered, forget; Identity, IPv4, IPv6, Security tabs; Save / Revert |
| `SecurityForm.qml`, `EapForm.qml`, `IpSettingsForm.qml`, `PathField.qml` | The forms of the details page and the dialogs |
| `HiddenNetworkDialog.qml` | A hidden network, or the 802.1X details of a new Enterprise network |
| `HotspotDialog.qml`, `HotspotActive.qml`, `QrCard.qml`, `ShareDialog.qml` | The hotspot, sharing by QR code |
| `Texts.js` | Wording (failure reasons, security names, bands, times) and checks |

New passwords are asked by the shell (Lumen's quick settings), the session's one secret prompter.

## Testing

Offscreen with the fake network service, a screenshot and an action:

```
MAIA_NETWORK_BACKEND=fake MAIA_NETWORK_SOCKET=$XDG_RUNTIME_DIR/maia/net-test.sock maia-network-service &
MAIA_NETWORK_SOCKET=$XDG_RUNTIME_DIR/maia/net-test.sock MAIA_FRONTENDS_PATH=<prefix>/frontends \
MAIA_SETTINGS_PAGES_PATH=apps/settings/pages QT_QPA_PLATFORM=offscreen \
    maia-settings --page network --action details:2 --screenshot ipv4.png
```

Actions of the Wi-Fi page: `hidden`, `enterprise`, `hotspot`, `hotspot-on`, `share`, `saved`,
`forget`, `details:<tab>`. Use an isolated `XDG_CONFIG_HOME`; never the real NetworkManager for
actions.
