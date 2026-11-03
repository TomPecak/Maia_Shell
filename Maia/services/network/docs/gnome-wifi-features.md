# Wi-Fi in GNOME: what the user interface offers

Reference for the Maia network service (`maia-network`, Cap'n Proto contract, QML module) and for the
Wi-Fi user interface of the Maia frontends. It describes what GNOME lets the user do with Wi-Fi, how the
interface behaves, and what each feature needs from NetworkManager. The last column of the tables is a
**proposal** for Maia (first version / later / skip), to be decided before the contract is written.

Scope: Wi-Fi only. Wired, VPN, mobile broadband and Bluetooth tethering appear in the same GNOME code,
but are left out here.

## Sources

| Source | Version | What it covers |
|---|---|---|
| `gnome-shell/js/ui/status/network.js` | 51.1-16-g7904014f5 | Quick settings: Wi-Fi toggle and its menu, status icon, failure notification, captive portal |
| `gnome-shell/js/ui/components/networkAgent.js` | same | The password dialog (NetworkManager secret agent) |
| `gnome-shell/js/ui/status/rfkill.js` | same | Airplane mode (through gnome-settings-daemon) |
| `gnome-control-center/panels/network/` | 51.0-92-gd5a89203f | Settings → Wi-Fi panel, saved networks, hidden network, hotspot, QR code, connection details editor |
| 13 screenshots, Ubuntu GNOME, Polish locale, 2026-11-03 | | Referred to below by their time stamp, e.g. *20-13-55* |

The screenshots are not part of the repository: *20-16-10* (QR code) shows a real network password.

GNOME spreads Wi-Fi over five places:

1. **Quick settings** in the top bar: a Wi-Fi toggle with a short network list (*20-16-25*).
2. **Password dialog**, shown by the shell when NetworkManager needs a password.
3. **Settings → Wi-Fi panel**, the full management (*20-13-55*).
4. **Dialogs** opened from the panel: saved networks (*20-14-14*), hidden network (*20-14-49*,
   *20-14-57*, *20-15-08*), hotspot (*20-15-21*), connection details (*20-15-36* to *20-15-53*), QR code
   (*20-16-10*).
5. **Notifications**: connection failed, sign in to network (captive portal).

---

## 1. Status icon in the top bar

One icon for the primary connection; for Wi-Fi it is chosen in this order (`NMWirelessDeviceItem.icon_name`):

| State | Icon |
|---|---|
| Wi-Fi turned off | `network-wireless-disabled` |
| Connecting or disconnecting | `network-wireless-acquiring` |
| Connected as a hotspot | `network-wireless-hotspot` |
| Connected, no internet (connectivity is not *full*) | `network-wireless-no-route` |
| Connected | signal level icon: none < 20 %, weak < 40 %, ok < 50 %, good < 80 %, excellent |
| Not connected | `network-wireless-signal-none` |

The whole indicator is hidden while NetworkManager is not running.

## 2. Quick settings: Wi-Fi toggle and menu

*20-16-25*. A split button: the left part is a toggle, the arrow opens the menu.

**Toggle**

- Title "Wi-Fi", subtitle the connected network's name (the connection name for a hidden network;
  "*device* Hotspot" while sharing).
- Click turns Wi-Fi on or off (NetworkManager `WirelessEnabled`). While a hotspot is active, the click
  stops the hotspot instead, and the menu is disabled.
- Insensitive while the hardware switch blocks Wi-Fi (`WirelessHardwareEnabled`) and while polkit does
  not allow `org.freedesktop.NetworkManager.network-control`.
- Hidden when there is no Wi-Fi device or networking is disabled.

**Menu**

- Header "Wi-Fi" with a spinner while a scan runs.
- At most **8 networks**. Each row shows the signal icon, a padlock for secured networks, the name, and a
  check mark on the connected one. The accessible name reads "name, Secure / Not secure, Signal strength N %".
- Click on a row connects (details in section 4).
- "All Networks" at the bottom opens the Settings Wi-Fi panel.
- With several Wi-Fi adapters every adapter is a submenu named after the device.

**Behaviour**

- **Scanning only while the menu is open**: one scan at once, then every 15 s; the spinner runs until the
  device's `LastScan` changes.
- **One row per network, not per access point**: access points with the same SSID, mode and security type
  are merged; the row shows the strongest one. Access points without an SSID (hidden) are not listed.
- **Order**: networks with a saved connection first, then by signal strength, then secured before open,
  then alphabetically.
- Enterprise (802.1X) networks without a saved connection are hidden on the lock screen.

## 3. Settings → Wi-Fi panel

*20-13-55*. The header bar shows the device state as subtitle ("Connected", "Connecting",
"Authentication required", "Connection failed", ...).

**Top group**

| Row | Function |
|---|---|
| Wi-Fi (switch) | Turns Wi-Fi on or off |
| Saved Networks › | Opens the saved networks dialog (section 6) |
| Connect to Hidden Network… › | Opens the hidden network dialog (section 7) |
| Turn On Wi-Fi Hotspot… › | Opens the hotspot dialog (section 8). Insensitive with tooltip "System policy prohibits use as a Hotspot" or "Wireless device does not support Hotspot mode" |

**Airplane mode** (own group): switch "Airplane Mode", subtitle "Disables Wi-Fi, Bluetooth and mobile
broadband". Insensitive while a hardware switch is on. Shown only when the system has airplane mode.

**Visible Networks** with a scanning spinner, a list of all networks. Each row:

- signal icon (tooltip "Signal strength N %"), padlock (tooltip "Secure network (WPA / WPA2 / WPA3)"),
  name, subtitle "Connected" on the active one, a spinner while connecting;
- buttons: **QR code** (share, only active or saved networks with a supported security type),
  **gear** (details, only active, connecting or saved networks);
- placeholder "Searching for networks…" while the list is empty;
- a saved connection whose name differs from the SSID shows "name (SSID: ssid)".

Order: the connected network first, then saved before unsaved, then by signal strength. Scanning every 15 s
while the panel is open.

**Empty states** (whole page replaced), in this priority:

| Condition | Page |
|---|---|
| NetworkManager not running | "Wi-Fi Unavailable" |
| Wi-Fi off and airplane mode on | "Airplane Mode On" |
| Hardware switch off or no adapter | "No Wi-Fi Adapter Found" |
| Wi-Fi off | "Wi-Fi Off" |

**Hotspot active**: the list is replaced by "Wi-Fi Hotspot Active", the QR code, the hotspot name,
security type and password, and "Turn Off Hotspot…" (with a confirmation).

**Several adapters**: one page per device, with a switcher; each device has its own list and switch.

## 4. Connecting to a network

What happens on a click on a network, in the menu and in the panel (`WirelessNetwork.activate`,
`wireless_try_to_connect`):

1. **Saved network**: NetworkManager activates the saved connection (`ActivateConnection`).
2. **New Enterprise (802.1X) network**: the Settings panel opens a dialog for the 802.1X details
   (`connect-8021x-wifi`), as a password alone is not enough.
3. **Any other new network**: NetworkManager creates and activates a connection from the access point
   (`AddAndActivateConnection` with an almost empty profile). Without polkit permission
   `settings.modify.system` the profile is limited to the current user (connection permission
   `user:<name>`). NetworkManager then asks the secret agent for the password (section 5).

Failure: a notification "Connection failed — Activation of network connection failed" (urgent, transient),
except when the reason is "no secrets", which means the user cancelled the password dialog. The
notification disappears once a connection succeeds.

## 5. Password dialog (secret agent)

gnome-shell registers as NetworkManager secret agent. When a connection needs secrets it shows a modal
dialog:

- title "Authentication required", text "Passwords or encryption keys are required to access the wireless
  network “SSID”";
- the fields depend on the security type:

| Security | Fields | Validation |
|---|---|---|
| WPA/WPA2/WPA3 Personal (`wpa-psk`, `sae`) | Password | 8–63 characters, or exactly 64 hexadecimal digits |
| Static WEP | Key | 5/13 characters or 10/26 hex digits (key); up to 64 characters (passphrase) |
| LEAP | Password | not empty |
| 802.1X / Enterprise | depending on the EAP method: Username, Password, Identity, Private key password | not empty |

- "Connect" is enabled only while every field is valid; "Cancel" refuses (NetworkManager ends with
  "no secrets", no failure notification).
- When the access point offers WPS push button: "Alternatively you can connect by pushing the “WPS” button
  on your router".
- Outside the dialog (e.g. on the lock screen) the request is shown as a notification instead.

## 6. Saved networks

*20-14-14*. Dialog "Saved Wi-Fi Networks", ordered by last use. Each row: signal and padlock icons, name,
"Connected" on the active one, buttons QR code, gear (details) and **forget** (trash).

- Forget hides the row at once and shows a toast "Network deleted" with **Undo**; the profile is deleted
  only when the toast goes away. Several deletions are counted ("3 networks deleted").
- Empty state "No Saved Networks".

## 7. Hidden network

*20-14-49*, *20-14-57*, *20-15-08*. Dialog "Connect to Hidden Wi-Fi Network" (from libnma):

- **Connection**: "New…" or one of the saved networks;
- **Network name** (SSID);
- **Wi-Fi security**: None, LEAP, WPA & WPA2 Personal, WPA & WPA2 Enterprise, WPA3 Personal, Enhanced
  Open; the fields of the chosen type follow (password, or the 802.1X details);
- "Connect" stays insensitive until the input is complete.

## 8. Hotspot

*20-15-21*. Dialog "Turn On Wi-Fi Hotspot?":

- explanation: other devices can use this computer's internet connection through a Wi-Fi network it
  creates; the computer needs internet from another source than Wi-Fi;
- warning with the network that will be disconnected ("Turning on the hotspot will disconnect from
  AndroidAP, and you will not be able to use the internet over Wi-Fi");
- **Network name**, prefilled with the computer's host name; errors "Network name cannot be empty",
  "Network name is too long";
- **Password**, empty means "Generate password automatically" (8 random characters); error "Password must
  have a minimum of 8 characters", at most 63;
- WPA-PSK, as WPA2 with CCMP when the adapter supports it (WPA with TKIP otherwise); the profile is a
  connection with IPv4 method *shared*, reused next time.

While active see section 3; the quick settings toggle shows "*device* Hotspot" and turns it off.

## 9. Sharing a network by QR code

*20-16-10*. Dialog "Share Network": the QR code, "Scan to Connect", the network name and the password in
plain text. The code is the usual Wi-Fi format `WIFI:S:<ssid>;T:<WPA|SAE|nopass>;P:<password>;H:true;`
(`H:true` for hidden networks; special characters escaped). The password comes from NetworkManager
(`GetSecrets` of the saved connection).

## 10. Connection details editor

Opened by the gear. A dialog with tabs, "Cancel" and "Apply".

**Details** (*20-15-36*), read-only facts while connected:

| Field | Example | NetworkManager source |
|---|---|---|
| Signal Strength | Weak / Ok / Good / Excellent | access point `Strength` |
| Link speed | 130 Mb/s (2.4 GHz) | device `Bitrate`, access point `Frequency` |
| Security | WPA2 | access point flags |
| IPv4 Address, IPv6 Address | | device `Ip4Config` / `Ip6Config` |
| Hardware Address | | device `HwAddress` |
| Supported Frequencies | 2.4 GHz / 5 GHz / 6 GHz | device `WirelessCapabilities` |
| Default Route, DNS | | IP configuration |
| Last Used (when not connected) | Today / Yesterday / N days ago / Never | connection `timestamp` |

Settings on the same tab:

- **Connect automatically** (`connection.autoconnect`);
- **Make available to other users** (no user permission in the profile; needs `settings.modify.system`);
- **Metered connection**: "has data limits or can incur charges — Software updates and other large
  downloads will not be started automatically" (`connection.metered`);
- **Forget Connection…** (destructive, confirmation "Forget Connection? Saved details for “X” will be
  permanently lost. This includes passwords and any network changes.").

**Identity** (*20-15-41*): SSID, BSSID (lock to one access point), MAC address (lock to one adapter),
cloned MAC address (an address, or Preserve / Permanent / Random / Stable / Stable per SSID).

**IPv4** (*20-15-45*): method Automatic (DHCP) / Manual / Link-Local Only / Shared to other computers /
Disable; manual addresses (address, netmask, gateway); DNS with "Automatic" switch and comma-separated
servers; DNS search domains; routes with "Automatic" switch (address, netmask, gateway, metric); "Use this
connection only for resources on its network" (never the default route).

**IPv6** (*20-15-50*): method Automatic / Automatic, DHCP only / Link-Local Only / Manual / Shared to other
computers / Disable; DNS, routes and "only for resources on its network" as for IPv4 (prefix instead of
netmask).

**Security** (*20-15-53*): the security type (None, Enhanced Open, LEAP, WPA & WPA2 Personal, WPA & WPA2
Enterprise, WPA3 Personal; WEP is no longer offered for new settings), the password with "Show password",
and for Enterprise the 802.1X page (EAP method, identities, certificates, inner authentication).

## 11. Captive portal (sign in to network)

When the primary connection is up and NetworkManager reports connectivity *portal*, the shell shows a
notification "Sign in to Network — *connection name*". Activating it opens GNOME's portal helper (a small
browser) or, without it, the default browser with NetworkManager's connectivity check address. When the
login is done (or connectivity becomes *full*) the notification goes away; a cancelled login is not asked
again until the connection changes.

## 12. Airplane mode

Shown in the Settings panel (and in quick settings as its own toggle). GNOME does not use NetworkManager
for it: gnome-settings-daemon's rfkill service (`AirplaneMode`, `HardwareAirplaneMode`, `HasAirplaneMode`,
`ShouldShowAirplaneMode`) blocks all radios, Wi-Fi, Bluetooth and mobile broadband. Maia has no
gnome-settings-daemon, so this needs its own implementation (rfkill), which concerns Bluetooth as well.

## 13. Device states and failure reasons

The panel turns NetworkManager's device state and state reason into text. For Wi-Fi the relevant ones:

- **States**: Unavailable, Disconnected, Connecting, Authentication required, Connected, Disconnecting,
  Connection failed, Unmanaged.
- **Reasons**: Secrets were required, but not provided; 802.1X supplicant disconnected / configuration
  failed / failed / took too long to authenticate; IP configuration failed / expired; DHCP client failed to
  start / error / failed; Connection disappeared; Firmware missing; Configuration failed.

The contract should carry these as an enumeration and let the frontend word them ("Wrong password?" is
more useful than "Secrets were required, but not provided").

---

## Summary: capabilities and what they need

Legend for the Maia column: **1** = first version, **2** = later, **—** = skip (left to KDE System
Settings or not needed).

| # | Capability | GNOME place | NetworkManager (D-Bus) | Also needs | Maia |
|---|---|---|---|---|---|
| 1 | Wi-Fi on/off | Quick settings, panel | `WirelessEnabled` (rw), `WirelessHardwareEnabled` | polkit `enable-disable-wifi` | **1** |
| 2 | Status: connected network, signal, connecting, no internet, off, hardware switch | Icon, toggle subtitle, panel subtitle | `PrimaryConnection`, `Connectivity`, device `State`, `ActiveAccessPoint`, AP `Strength` | | **1** |
| 3 | List of networks, merged by SSID, signal, secured, connected, saved | Menu (8), panel (all) | device `AccessPoints`, AP `Ssid`/`Strength`/`Flags`/`WpaFlags`/`RsnFlags`/`Mode`, device `AvailableConnections` | | **1** |
| 4 | Scan while the list is open, scanning indicator | Menu, panel | device `RequestScan`, `LastScan` | | **1** |
| 5 | Connect to a saved network | Menu, panel | `ActivateConnection` | | **1** |
| 6 | Connect to a new Personal/open network, with password | Menu, panel | `AddAndActivateConnection` | secret agent (or the password in the new profile), polkit | **1** |
| 7 | Password dialog with validation (8–63 / 64 hex) | Shell dialog | `SecretAgent.GetSecrets` / `CancelGetSecrets`, `AgentManager.Register` | | **1** |
| 8 | Disconnect | (menu: by turning Wi-Fi off) | `DeactivateConnection` or device `Disconnect` | | **1** |
| 9 | Failure message with a useful reason | Notification, panel subtitle | device `StateReason` | notifications (TODO.md item 3) | **1** |
| 10 | Saved networks, ordered by last use | Dialog | `Settings.ListConnections`, `GetSettings` (`timestamp`) | | **1** |
| 11 | Forget a network, with undo | Saved networks, details | `Connection.Delete` | | **1** |
| 12 | Details: signal, speed, band, security, addresses, MAC, gateway, DNS, last used | Details tab | device `Bitrate`/`HwAddress`/`Ip4Config`/`Ip6Config`, AP `Frequency` | | **1** (read-only) |
| 13 | Connect automatically | Details tab | `Connection.Update` (`autoconnect`) | | **1** |
| 14 | Hidden network (SSID + security + password) | Dialog | `AddAndActivateConnection` with `hidden=true` | | **2** |
| 15 | Share by QR code | Panel, saved networks | `Connection.GetSecrets` | QR code generator in the frontend | **2** |
| 16 | Hotspot (name, generated password, shared IPv4, turn off) | Dialog, panel, toggle | `AddAndActivateConnection` (mode `ap`, `ipv4.method=shared`), `GetPermissions` (`wifi.share.*`), `WirelessCapabilities` | | **2** |
| 17 | Metered connection | Details tab | `connection.metered` | | **2** |
| 18 | Available to other users | Details tab | connection `permissions` | polkit `settings.modify.system` | **2** |
| 19 | Captive portal: notice and sign-in | Notification | `Connectivity == PORTAL`, `ConnectivityCheckUri`, `CheckConnectivity` | browser or portal window, notifications | **2** |
| 20 | Airplane mode | Panel, quick settings | (not NetworkManager) | rfkill, Bluetooth service | **2** |
| 21 | Several Wi-Fi adapters | Submenus, device pages | devices of type Wi-Fi | | **2** (contract ready from the start) |
| 22 | Enterprise (802.1X): EAP method, identities, certificates | Dialogs, Security tab | `802-1x` settings, secrets | certificate file picker | **2** |
| 23 | Manual IPv4/IPv6, DNS, routes | IPv4/IPv6 tabs | `Connection.Update` (`ipv4`, `ipv6`) | | — (KDE System Settings) |
| 24 | BSSID, MAC lock, cloned/random MAC | Identity tab | `802-11-wireless` settings | | — |
| 25 | LEAP, WEP | Security tab, password dialog | | | — |
| 26 | WPS push button hint | Password dialog | secret agent flag `WPS_PBC_ACTIVE` | | — |

## Notes for Maia

Worth taking over:

- **Networks, not access points**: merge by SSID, mode and security type, show the strongest access point.
  Hide access points without SSID; hidden networks go through their own dialog.
- **Scan only while a list is visible**, at once and then every 15 s, with a visible "scanning" state.
- **Order**: connected first, saved before unsaved, stronger before weaker, secured before open, then by
  name. Enhanced Open (OWE) counts as not secured (no padlock), as there is no password.
- **Two depths**: a short list (8 networks) where the toggle is, the full list and the details in a
  separate view; Enterprise and hidden networks only in the full view.
- **Forget with undo** instead of a confirmation dialog in the list; a confirmation only in the details
  view, where forgetting is one of several actions.
- **No failure message when the user cancelled the password dialog**.
- **Password validation before Connect is enabled**, not after a failed attempt.

To decide for Maia:

- **Who asks for passwords**. GNOME's shell is the secret agent. In a Maia session that would be the
  network service, forwarding the request over the contract to whichever frontend is active (it shows the
  dialog in its own style). KDE's kded module `networkmanagement` registers an agent as well when kded
  runs; only one should answer. An alternative for the first version is to put the password into the new
  profile directly (as `nmcli` does), stored by NetworkManager in a file only root can read; then no agent
  is needed until a password is wrong or a saved one is missing. KWallet is disabled in Maia
  (`Maia/DeployFiles/etc/xdg/kwalletrc`), so secrets owned by an agent would need another store.
- **Notifications**: failures and captive portals need the notification service (TODO.md item 3), or a
  message inside the Wi-Fi view until it exists.
- **Airplane mode** is not a NetworkManager feature; it belongs with Bluetooth (rfkill).
- **Testing**: every action changes the real machine's network, also in a nested session. Actions are
  tested against a fake NetworkManager on a private bus; only reads may use the real one.
