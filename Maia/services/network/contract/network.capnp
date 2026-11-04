@0xdb704a23953a4ef5;

# Contract of the Maia network service (maia.network, version 1).
#
# The service (service/, Rust, maia-network-service) is the only process of the session that talks
# to NetworkManager. Shells, Maia Settings and apps (qml/, the Maia.Network QML module) read the state
# of the network and change it through this contract, over the Unix socket
#   $XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock
# (one per session: a nested development session has its own).
#
# What the user interface should offer, and where it comes from in GNOME, is in
# docs/gnome-wifi-features.md; the numbers there ("#14 hidden network") are referred to below.
#
# Rules:
# - Everything is identified by a stable id, never by a position in a list:
#     devices      by their interface name ("wlp2s0"),
#     networks     by an id the service makes (device, SSID, security), see WifiNetwork.id,
#     connections  by the UUID of the NetworkManager profile.
# - watch() sends the whole state first (snapshot), then only changes, as long as the client keeps
#   the returned Subscription. A changed object is sent whole (they are small). Changes of one object
#   come at most every 250 ms with its latest state: signal strengths change all the time.
# - Nothing here blocks: every call returns as soon as the service has handed the request to
#   NetworkManager. What happens next (connecting, connected, failed) arrives through the listener.
# - Reading, changing and answering password requests are separate capabilities: a status icon
#   only needs watch(); only the shell registers a SecretPrompter.
# - Texts for people are not part of the contract: states, reasons, security types and secret
#   fields are enumerations, and every frontend words them in its own language and style.
# - Results that the user has to see are values (Result), not exceptions. A Cap'n Proto exception
#   means the call itself failed (service gone, bug).

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaNetwork::Contract");

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------

enum ErrorCode {
  none @0;
  notFound @1;            # no such device, network or connection (any more)
  notAllowed @2;          # polkit refused (or the user cancelled the authentication)
  invalidArgument @3;     # e.g. an SSID longer than 32 bytes, a WPA password of 7 characters
  notSupported @4;        # e.g. the adapter cannot be a hotspot
  unavailable @5;         # NetworkManager is not running, Wi-Fi is off, the device is unavailable
  failed @6;              # NetworkManager refused; Result.message has its text (for logs)
}

struct Result {
  error @0 :ErrorCode;    # none = success
  message @1 :Text;       # technical detail for logs, not for the user interface
}

# ---------------------------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------------------------

enum Connectivity {
  unknown @0;             # not checked (yet), or checking is turned off
  none @1;                # no network
  portal @2;              # a captive portal: sign in before the internet works (#19)
  limited @3;             # a network, but no internet
  full @4;
}

enum Permission {
  no @0;
  auth @1;                # allowed after the user authenticates (polkit dialog)
  yes @2;
}

# What polkit allows this user (NetworkManager GetPermissions)
struct Permissions {
  enableDisableWifi @0 :Permission;     # switch Wi-Fi on and off (#1)
  networkControl @1 :Permission;        # connect and disconnect
  modifyOwn @2 :Permission;             # change own connections
  modifySystem @3 :Permission;          # connections for all users (#18)
  wifiShareOpen @4 :Permission;         # open hotspot
  wifiShareProtected @5 :Permission;    # hotspot with a password (#16)
}

enum ConnectionType {
  none @0;
  wifi @1;
  ethernet @2;
  vpn @3;
  other @4;
}

# The connection the system uses for the internet (NetworkManager PrimaryConnection, or the one
# being activated)
struct PrimaryConnection {
  type @0 :ConnectionType;
  name @1 :Text;          # profile name; for Wi-Fi usually the SSID
  uuid @2 :Text;
  deviceId @3 :Text;      # interface name, empty when none
  activating @4 :Bool;    # still being activated
}

struct Status {
  running @0 :Bool;                     # NetworkManager is running; false: everything else is empty
  networkingEnabled @1 :Bool;
  wirelessEnabled @2 :Bool;             # the software switch (#1)
  wirelessHardwareEnabled @3 :Bool;     # false: a hardware switch blocks Wi-Fi, the software one is
                                        # insensitive
  connectivity @4 :Connectivity;
  connectivityCheckUri @5 :Text;        # the address to open for signing in at a captive portal (#19)
  primary @6 :PrimaryConnection;
  permissions @7 :Permissions;
}

# The device states of NetworkManager that matter to the user interface
enum DeviceState {
  unknown @0;
  unmanaged @1;           # not handled by NetworkManager (not listed by GNOME)
  unavailable @2;         # e.g. Wi-Fi off, firmware missing
  disconnected @3;
  connecting @4;          # prepare, config, IP configuration, IP check, secondaries
  needAuth @5;            # waiting for secrets (a SecretRequest is out)
  connected @6;
  disconnecting @7;
  failed @8;
}

# Why a device is in its state (NetworkManager device state reason), for the failure messages
# (#9). Reasons not listed here arrive as `other`.
enum StateReason {
  none @0;
  other @1;
  noSecrets @2;           # the user cancelled the password dialog: show no failure
  wrongSecrets @3;        # the supplicant disconnected while authenticating: usually a wrong password
  supplicantFailed @4;
  supplicantTimeout @5;   # authentication took too long
  configFailed @6;
  ipConfigFailed @7;      # DHCP and the like
  ipConfigExpired @8;
  connectionRemoved @9;   # the profile was deleted
  ssidNotFound @10;       # the network is out of reach
  firmwareMissing @11;
  userRequested @12;      # disconnected on purpose
  carrierLost @13;
}

# Bands an adapter or an access point uses
const band24GHz :UInt8 = 0x1;
const band5GHz :UInt8 = 0x2;
const band6GHz :UInt8 = 0x4;

struct IpAddress {
  address @0 :Text;       # "192.168.1.20", "fe80::1"
  prefix @1 :UInt8;       # 24, 64
}

# The IP configuration of an active connection (details, #12)
struct IpInfo {
  addresses @0 :List(IpAddress);
  gateway @1 :Text;
  dns @2 :List(Text);
}

struct WifiDevice {
  id @0 :Text;                    # interface name, e.g. "wlp2s0"
  name @1 :Text;                  # a name telling several adapters apart: "Intel AX201", or "" when
                                  # there is only one (the frontend then says "Wi-Fi")
  hwAddress @2 :Text;             # current MAC address
  permHwAddress @3 :Text;         # permanent MAC address
  state @4 :DeviceState;
  stateReason @5 :StateReason;
  activeNetworkId @6 :Text;       # WifiNetwork.id, empty when not connected
  activeConnectionUuid @7 :Text;  # the profile in use, also for a hidden network or a hotspot
  hotspot @8 :Bool;               # the device shares a connection (an access point, #16)
  bitrate @9 :UInt32;             # current link speed in kbit/s, 0 when not connected
  bands @10 :UInt8;               # band* bits the adapter supports
  canHotspot @11 :Bool;           # the adapter can be an access point
  scanning @12 :Bool;             # a scan runs (requestScan until LastScan changes)
  lastScan @13 :Int64;            # ms since 1970, 0 = never
  ip4 @14 :IpInfo;                # of the active connection, empty when not connected
  ip6 @15 :IpInfo;
}

enum Security {
  none @0;                # open
  enhancedOpen @1;        # OWE: encrypted, no password; shown without padlock like GNOME
  wep @2;
  leap @3;
  wpaPersonal @4;         # WPA/WPA2 with a password (PSK)
  wpa3Personal @5;        # SAE
  wpaEnterprise @6;       # WPA/WPA2 802.1X (#22)
  wpa3Enterprise @7;
}

enum WifiMode {
  infrastructure @0;
  adhoc @1;
  accessPoint @2;
}

struct AccessPoint {
  bssid @0 :Text;
  strength @1 :UInt8;     # 0..100
  frequency @2 :UInt32;   # MHz
  maxBitrate @3 :UInt32;  # kbit/s
  lastSeen @4 :Int64;     # ms since 1970
}

# A network the device sees: the access points with the same SSID, mode and security merged into
# one (#3), as GNOME does. Access points without an SSID (hidden) are not listed; a hidden network is
# joined through connectHidden() (#14).
struct WifiNetwork {
  id @0 :Text;                    # stable while the network is visible: "<deviceId>/<ssid in hex>/<security>"
  deviceId @1 :Text;
  ssid @2 :Data;                  # the raw SSID (up to 32 bytes, not necessarily UTF-8)
  name @3 :Text;                  # the SSID as text (invalid UTF-8 replaced)
  security @4 :Security;
  mode @5 :WifiMode;
  strength @6 :UInt8;             # of the strongest access point, 0..100
  frequency @7 :UInt32;           # of the strongest access point, MHz
  bands @8 :UInt8;                # band* bits seen among its access points
  connectionUuids @9 :List(Text); # saved profiles that fit it (#5); empty = a new network
  active @10 :Bool;               # the device is connected (or connecting) to it
  accessPoints @11 :List(AccessPoint);  # strongest first
}

enum Metered {
  unknown @0;             # NetworkManager guesses (e.g. a phone hotspot)
  yes @1;
  no @2;
}

# A saved Wi-Fi profile (#10), also when its network is not in reach
struct SavedConnection {
  uuid @0 :Text;
  name @1 :Text;          # profile name (shown "name (SSID: ssid)" when it differs, like GNOME)
  ssid @2 :Data;
  ssidText @3 :Text;
  security @4 :Security;
  hidden @5 :Bool;
  hotspot @6 :Bool;       # an access point profile made for the hotspot (#16)
  autoconnect @7 :Bool;
  metered @8 :Metered;
  availableToAll @9 :Bool;  # no user permission in the profile (#18)
  lastUsed @10 :Int64;    # ms since 1970, 0 = never (the profile's timestamp)
  activeDeviceId @11 :Text; # where it is active, empty when not
  qrSupported @12 :Bool;  # sharing by QR code works for its security type (#15)
}

struct Snapshot {
  status @0 :Status;
  devices @1 :List(WifiDevice);
  networks @2 :List(WifiNetwork);
  connections @3 :List(SavedConnection);
}

# Something that happened, not a state: the frontend may show it once (a notification, a message in
# the Wi-Fi view) and forget it
struct Event {
  union {
    activationFailed @0 :ActivationFailed;   # #9; not sent for reason noSecrets
    connected @1 :Text;                      # connection UUID that has just been activated
  }
}

struct ActivationFailed {
  deviceId @0 :Text;
  connectionUuid @1 :Text;
  name @2 :Text;          # network or profile name
  reason @3 :StateReason;
}

# Receiver of the state.
# Messages about one object arrive in order (changed..., removed); messages about different objects
# may arrive in any order relative to each other.
interface NetworkListener {
  snapshot @0 (snapshot :Snapshot);            # the whole state, the first call after watch()
  statusChanged @1 (status :Status);
  deviceChanged @2 (device :WifiDevice);       # added or changed
  deviceRemoved @3 (id :Text);
  networkChanged @4 (network :WifiNetwork);    # appeared or changed
  networkRemoved @5 (id :Text);                # out of reach
  connectionChanged @6 (connection :SavedConnection);  # saved or changed
  connectionRemoved @7 (uuid :Text);
  event @8 (event :Event);
}

# Handle of a subscription or a registration: dropping it ends it in the service
interface Subscription {}

# ---------------------------------------------------------------------------------------------
# Connection settings (the details editor, #12, #13, #17, #18, #22 - #25)
# ---------------------------------------------------------------------------------------------

enum IpMethod {
  auto @0;                # DHCP (IPv4); SLAAC and DHCP (IPv6)
  dhcpOnly @1;            # IPv6 only: "Automatic, DHCP only"
  manual @2;
  linkLocal @3;
  shared @4;              # shared to other computers
  disabled @5;
}

struct Route {
  destination @0 :Text;
  prefix @1 :UInt8;
  gateway @2 :Text;
  metric @3 :Int64;       # -1 = default
}

struct IpSettings {
  method @0 :IpMethod;
  addresses @1 :List(IpAddress);      # manual
  gateway @2 :Text;                   # manual
  autoDns @3 :Bool;
  dns @4 :List(Text);
  dnsSearch @5 :List(Text);
  autoRoutes @6 :Bool;
  routes @7 :List(Route);
  neverDefault @8 :Bool;              # "Use this connection only for resources on its network"
}

enum ClonedMac {
  default @0;             # NetworkManager's global default
  preserve @1;
  permanent @2;
  random @3;
  stable @4;
  stableSsid @5;
  address @6;             # WifiSettings.clonedMacAddress
}

struct WifiSettings {
  ssid @0 :Data;
  hidden @1 :Bool;
  bssid @2 :Text;                     # lock to one access point, empty = any
  macAddress @3 :Text;                # lock to one adapter, empty = any
  clonedMac @4 :ClonedMac;
  clonedMacAddress @5 :Text;
}

enum EapMethod {
  tls @0;
  peap @1;
  ttls @2;
  pwd @3;
  fast @4;
  leap @5;
}

enum InnerAuth {
  mschapv2 @0;
  mschap @1;
  pap @2;
  chap @3;
  gtc @4;
  md5 @5;
}

# 802.1X (Enterprise, #22). Files are paths; the private key password and the password are secrets
# (see Secrets), not here.
struct Eap8021xSettings {
  method @0 :EapMethod;
  identity @1 :Text;
  anonymousIdentity @2 :Text;
  caCertificate @3 :Text;             # file path, empty = none
  noCaCertificate @4 :Bool;           # the user chose "No CA certificate is required"
  domain @5 :Text;                    # domain to match the server certificate against
  clientCertificate @6 :Text;         # TLS
  privateKey @7 :Text;                # TLS
  innerAuth @8 :InnerAuth;            # PEAP, TTLS, FAST
  pacFile @9 :Text;                   # FAST
  peapVersion @10 :Int8;              # -1 = automatic, 0, 1
}

struct SecuritySettings {
  security @0 :Security;
  wepKeyIndex @1 :UInt8;              # 0..3
  wepPassphrase @2 :Bool;             # the WEP key is a passphrase (else hex or ASCII key)
  leapUsername @3 :Text;
  eap @4 :Eap8021xSettings;           # for wpaEnterprise, wpa3Enterprise
}

struct ConnectionSettings {
  name @0 :Text;
  autoconnect @1 :Bool;
  metered @2 :Metered;
  availableToAll @3 :Bool;
  wifi @4 :WifiSettings;
  security @5 :SecuritySettings;
  ip4 @6 :IpSettings;
  ip6 @7 :IpSettings;
}

# Secrets of a connection: what the password dialog fills in and what sharing shows (#7, #15)
struct Secret {
  key @0 :SecretKey;
  value @1 :Text;
}

enum SecretKey {
  wifiPassword @0;        # WPA/WPA3 Personal passphrase (or 64 hex digits)
  wepKey @1;
  leapPassword @2;
  eapPassword @3;
  eapPrivateKeyPassword @4;
  eapIdentity @5;         # asked together with the password when it is not saved
}

# ---------------------------------------------------------------------------------------------
# Password requests (the secret agent, #7)
# ---------------------------------------------------------------------------------------------

# How the frontend checks a field before it enables "Connect"
enum Validation {
  notEmpty @0;
  wpaPassword @1;         # 8..63 characters, or exactly 64 hexadecimal digits
  wepKey @2;              # 5 or 13 characters, or 10 or 26 hexadecimal digits
  wepPassphrase @3;       # 1..64 characters
}

struct SecretField {
  key @0 :SecretKey;
  value @1 :Text;         # prefilled (e.g. the identity, or the refused password to correct)
  hidden @2 :Bool;        # a password: dots, with "show password"
  validation @3 :Validation;
}

# NetworkManager needs secrets for a connection. The service is the secret agent of the session and
# passes the request to the registered prompter (the shell), which shows the dialog.
struct SecretRequest {
  id @0 :Text;                    # for cancel()
  connectionUuid @1 :Text;
  name @2 :Text;                  # network or profile name for the dialog
  deviceId @3 :Text;
  security @4 :Security;
  fields @5 :List(SecretField);
  retry @6 :Bool;                 # the saved secret was refused: "Wrong password?"
  wpsPushButton @7 :Bool;         # the access point offers WPS push button (#26)
}

struct SecretReply {
  union {
    cancelled @0 :Void;           # the user cancelled: the connection ends with noSecrets
    secrets @1 :List(Secret);
  }
}

# Implemented by the shell. At most one prompter is registered at a time; a new registration
# replaces the old one (e.g. after a frontend switch).
interface SecretPrompter {
  # Asks the user; returns when the user answered. May take minutes.
  ask @0 (request :SecretRequest) -> (reply :SecretReply);
  # NetworkManager no longer needs the answer (timeout, the connection was cancelled):
  # close the dialog of this request; the pending ask() is answered by the service
  cancel @1 (id :Text);
}

# ---------------------------------------------------------------------------------------------
# The service
# ---------------------------------------------------------------------------------------------

interface NetworkService {
  # Name of the backend ("networkmanager", or "fake" for tests) and the service version
  info @0 () -> (backend :Text, serviceVersion :Text);

  # The state: snapshot first, then changes, while the client keeps the subscription
  watch @1 (listener :NetworkListener) -> (subscription :Subscription);

  # Changing things (a separate capability)
  control @2 () -> (control :NetworkControl);

  # Registers the shell as the one that asks the user for passwords, while it keeps the
  # registration. Without a prompter, requests are answered as cancelled.
  registerPrompter @3 (prompter :SecretPrompter) -> (registration :Subscription);
}

enum HotspotPasswordKind {
  generate @0;            # 8 random characters, like GNOME
  given @1;
}

interface NetworkControl {
  # #1
  setWirelessEnabled @0 (enabled :Bool) -> (result :Result);

  # Scans now (#4); deviceId "" = every Wi-Fi device. NetworkManager limits how often it scans.
  requestScan @1 (deviceId :Text) -> (result :Result);

  # Connects to a visible network (#5, #6): with its saved profile, else with a new profile made
  # from the network (limited to this user without the modifySystem permission). Secrets are asked
  # through the SecretPrompter when NetworkManager needs them. Enterprise networks need
  # connectWithSettings() (802.1X details first).
  connect @2 (networkId :Text) -> (result :Result);

  # Activates a saved profile on a device (also a hidden network or a hotspot profile)
  activate @3 (uuid :Text, deviceId :Text) -> (result :Result);

  # A new connection from settings: a hidden network (#14) or an Enterprise network (#22).
  # secrets: what the user typed in the same dialog (saved into the profile).
  connectWithSettings @4 (deviceId :Text, settings :ConnectionSettings, secrets :List(Secret))
      -> (result :Result, uuid :Text);

  # Disconnects the device (#8)
  disconnect @5 (deviceId :Text) -> (result :Result);

  # Deletes a saved profile (#11). The undo of the user interface is the frontend's: it waits with
  # this call until its undo message is gone.
  forget @6 (uuid :Text) -> (result :Result);

  # The settings of a profile for the details editor, without secrets
  settings @7 (uuid :Text) -> (result :Result, settings :ConnectionSettings);

  # Saves changed settings (#13, #17, #18, #23 - #25); secrets only when the user changed them
  updateSettings @8 (uuid :Text, settings :ConnectionSettings, secrets :List(Secret))
      -> (result :Result);

  # The saved secrets of a profile ("show password", sharing). Asks polkit when needed.
  secrets @9 (uuid :Text) -> (result :Result, secrets :List(Secret));

  # Sharing by QR code (#15): the Wi-Fi QR text "WIFI:S:...;T:...;P:...;;" and its modules
  # (size x size, row by row, 1 = dark), so a frontend only draws squares
  qrCode @10 (uuid :Text) -> (result :Result, text :Text, size :UInt32, modules :Data);

  # Hotspot (#16): makes or reuses the hotspot profile, starts it; returns the profile and the
  # password in use. ssid "" = the host name.
  startHotspot @11 (deviceId :Text, ssid :Text, passwordKind :HotspotPasswordKind, password :Text)
      -> (result :Result, uuid :Text, password :Text);
  stopHotspot @12 (deviceId :Text) -> (result :Result);

  # Checks connectivity again now (after signing in at a captive portal, #19)
  checkConnectivity @13 () -> (result :Result);
}
