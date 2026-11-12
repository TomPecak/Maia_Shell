@0xb5d2c7e19a3f8064;

# Contract of the Maia power service (maia.power, version 1).
#
# The service (service/, Rust, maia-power-service) is the only process of a Maia session that reads
# and changes the power state of the machine: the batteries (of the computer and of devices such as
# a mouse or headphones), the brightness of the screens and of the keyboard backlight, and the power
# profile. Shells, Maia Settings and apps (qml/, the Maia.Power QML module) use it through this
# contract, over the Unix socket
#   $XDG_RUNTIME_DIR/maia/power-$WAYLAND_DISPLAY.sock
# (one per session: a nested development session has its own).
#
# It uses the system's own services, nothing of a desktop environment: UPower (batteries, the
# charger, the lid, the keyboard backlight), the kernel's backlight devices (read from sysfs,
# written through systemd-logind's Session.SetBrightness, which needs no administrator rights) and
# power-profiles-daemon.
#
# Rules:
# - Everything is identified by a stable id, never by a position in a list:
#     batteries  by UPower's device name ("battery_BAT0", "mouse_dev_F4_73_35_xx_xx_xx"),
#     displays   by "<source>:<device>" ("backlight:intel_backlight").
# - watch() sends the whole state first (snapshot), then only changes, as long as the client keeps
#   the returned Subscription. A changed object is sent whole (they are small). Changes of one object
#   come at most every 50 ms with its latest state.
# - Fractions are 0.0 .. 1.0 (brightness) and percentages 0 .. 100 (batteries), as their sources give
#   them; times are seconds, 0 when unknown.
# - Nothing here blocks: a change returns once it has been handed to its source; the new state
#   arrives through the listener. Brightness requests are coalesced: while one is being applied, only
#   the latest of the following ones is applied next (a dragged slider sends many).
# - What is missing is a state, not an error: no battery (a desktop computer), no backlight (an
#   external monitor), no power-profiles-daemon. Each part says whether it is available.
# - Texts for people are not part of the contract: kinds, states and events are enumerations, and
#   every frontend words them in its own language and style.
# - Results that the user has to see are values (Result), not exceptions. A Cap'n Proto exception
#   means the call itself failed (service gone, bug).

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaPower::Contract");

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------

enum ErrorCode {
  none @0;
  notFound @1;            # no such display (any more)
  notAllowed @2;          # logind or polkit refused (e.g. the session is not the active one)
  invalidArgument @3;     # e.g. a brightness outside 0 .. 1
  notSupported @4;        # e.g. no keyboard backlight on this machine
  unavailable @5;         # the source does not run (UPower, power-profiles-daemon)
  failed @6;              # the source refused; Result.message has its text (for logs)
}

struct Result {
  error @0 :ErrorCode;    # none = success
  message @1 :Text;       # technical detail for logs, not for the user interface
}

# ---------------------------------------------------------------------------------------------
# Batteries (UPower)
# ---------------------------------------------------------------------------------------------

enum DeviceKind {
  battery @0;             # a battery of the computer (laptop, tablet)
  ups @1;
  mouse @2;
  keyboard @3;
  touchpad @4;
  gamingInput @5;
  pen @6;
  headset @7;
  headphones @8;
  speakers @9;
  phone @10;
  tablet @11;
  mediaPlayer @12;
  computer @13;
  wearable @14;
  other @15;
}

enum BatteryState {
  unknown @0;
  charging @1;
  discharging @2;
  empty @3;
  full @4;
  pendingCharge @5;       # plugged in, charging has not started (e.g. a charge threshold)
  pendingDischarge @6;
}

# How urgent the level of a battery is (UPower's warning level; its thresholds are UPower's)
enum WarningLevel {
  none @0;
  low @1;
  critical @2;
  action @3;              # so low that the system is about to suspend or power off
}

struct Battery {
  id @0 :Text;
  kind @1 :DeviceKind;
  vendor @2 :Text;
  model @3 :Text;         # "MX Master 3", "5B10W51867"
  present @4 :Bool;       # a battery bay can be empty
  powerSupply @5 :Bool;   # powers the computer (false: a device's own battery)
  percentage @6 :Float64; # 0 .. 100
  state @7 :BatteryState;
  warningLevel @8 :WarningLevel;
  timeToEmpty @9 :Int64;  # seconds, 0 = unknown
  timeToFull @10 :Int64;  # seconds, 0 = unknown
  energyRate @11 :Float64;# watts drawn or charged, 0 = unknown
  capacity @12 :Float64;  # health: the full capacity in percent of the design capacity, 0 = unknown
  iconName @13 :Text;     # a freedesktop icon name for the state ("battery-level-80-symbolic")
}

struct PowerStatus {
  upowerAvailable @0 :Bool;
  onBattery @1 :Bool;     # no charger: the computer runs from its battery
  lidPresent @2 :Bool;
  lidClosed @3 :Bool;
  # The battery of the computer as one (UPower's display device: all its batteries together);
  # present = false on a computer without a battery
  summary @4 :Battery;
}

# ---------------------------------------------------------------------------------------------
# Brightness
# ---------------------------------------------------------------------------------------------

enum DisplayKind {
  builtIn @0;             # the panel of a laptop (a kernel backlight device)
  external @1;            # a monitor (DDC/CI; not yet)
}

struct Display {
  id @0 :Text;
  kind @1 :DisplayKind;
  device @2 :Text;        # the kernel's name ("intel_backlight"), for logs and debugging
  brightness @3 :Float64; # 0 .. 1
  rawBrightness @4 :UInt32;
  rawMaximum @5 :UInt32;  # the number of steps the hardware has
  minimum @6 :Float64;    # the lowest brightness setBrightness gives (never off: some panels go black at 0)
}

struct KeyboardBacklight {
  available @0 :Bool;
  brightness @1 :Float64; # 0 .. 1
  rawBrightness @2 :UInt32;
  rawMaximum @3 :UInt32;
}

# ---------------------------------------------------------------------------------------------
# Power profiles (power-profiles-daemon)
# ---------------------------------------------------------------------------------------------

enum Profile {
  powerSaver @0;
  balanced @1;
  performance @2;
}

enum Degradation {
  none @0;
  lapDetected @1;         # the computer is on a lap: performance is limited
  highOperatingTemperature @2;
  other @3;
}

struct HeldProfile {
  profile @0 :Profile;
  reason @1 :Text;        # given by the application ("Compiling", "Playing a game")
  applicationId @2 :Text; # "org.kde.konsole"
}

struct Profiles {
  available @0 :Bool;     # power-profiles-daemon runs
  active @1 :Profile;
  offered @2 :List(Profile);   # the profiles this machine has (performance is not always there)
  degraded @3 :Degradation;    # why performance is limited now
  holds @4 :List(HeldProfile); # applications that hold a profile (the system's, not only Maia's)
}

# ---------------------------------------------------------------------------------------------
# Events: for notifications ("Battery low", "Charger connected")
# ---------------------------------------------------------------------------------------------

enum EventKind {
  chargerConnected @0;
  chargerDisconnected @1;
  batteryLow @2;          # the computer's battery reached the low level (summary)
  batteryCritical @3;
  batteryAction @4;       # the system will act (suspend, power off) very soon
  batteryFull @5;         # charged while the charger is connected
  deviceBatteryLow @6;    # a device's battery (mouse, headphones) reached the low level
}

struct Event {
  kind @0 :EventKind;
  batteryId @1 :Text;     # the battery it concerns ("" for the charger)
  percentage @2 :Float64;
}

# ---------------------------------------------------------------------------------------------
# The service
# ---------------------------------------------------------------------------------------------

struct Snapshot {
  status @0 :PowerStatus;
  batteries @1 :List(Battery);  # every battery, the computer's and the devices'
  displays @2 :List(Display);
  keyboard @3 :KeyboardBacklight;
  profiles @4 :Profiles;
}

interface PowerListener {
  snapshot @0 (snapshot :Snapshot);           # the whole state, the first call after watch()
  statusChanged @1 (status :PowerStatus);
  batteryChanged @2 (battery :Battery);       # appeared or changed
  batteryRemoved @3 (id :Text);
  displayChanged @4 (display :Display);       # appeared or changed
  displayRemoved @5 (id :Text);
  keyboardChanged @6 (keyboard :KeyboardBacklight);
  profilesChanged @7 (profiles :Profiles);
  event @8 (event :Event);
}

# Kept by the client as long as it listens; dropping it ends the listening
interface Subscription {}

# Kept by the client as long as the profile is to be held; dropping it (or disconnecting) releases it
interface ProfileHold {}

interface PowerService {
  # The service and its backend ("system", or "fake": simulated, for tests and nested sessions)
  info @0 () -> (serviceVersion :Text, backend :Text);
  watch @1 (listener :PowerListener) -> (subscription :Subscription);
  control @2 () -> (control :PowerControl);
}

interface PowerControl {
  # displayId "" = the built-in screen (or the first display). brightness 0 .. 1, raised to the
  # display's minimum.
  setBrightness @0 (displayId :Text, brightness :Float64) -> (result :Result);
  # Up (steps > 0) or down by steps of 5 %, never below the minimum: the brightness keys, the wheel
  stepBrightness @1 (displayId :Text, steps :Int32) -> (result :Result);
  setKeyboardBrightness @2 (brightness :Float64) -> (result :Result);
  setProfile @3 (profile :Profile) -> (result :Result);
  # Holds a profile while the returned capability lives (e.g. performance while compiling); the
  # profile the user chose comes back when the last hold ends. reason and applicationId are shown
  # to the user.
  holdProfile @4 (profile :Profile, reason :Text, applicationId :Text) -> (result :Result, hold :ProfileHold);
}
