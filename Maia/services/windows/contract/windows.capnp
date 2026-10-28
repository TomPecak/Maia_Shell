@0xc1eb90c847edb209;

# Contract of the Maia window service (maia.windows, version 1).
#
# The service (service/, Rust) is the only process that talks to the compositor about the windows of
# other applications. Shells and apps (qml/, the Maia.Windows QML module) get the list of windows
# and control them through this contract, over the Unix socket
#   $XDG_RUNTIME_DIR/maia/windows-$WAYLAND_DISPLAY.sock
#
# Rules:
# - Data and control only. Streams and anything tied to frames (live window previews, minimize
#   animations, drawing) do not go through the service: the client talks to the compositor or to
#   PipeWire directly.
# - Windows are identified by a stable id (the UUID given by the compositor), never by a position
#   in a list: positions shift between processes.
# - watch() sends the whole state first (snapshot), then only changes (added / changed / removed),
#   as long as the client keeps the returned Subscription.
# - Reading and control are separate capabilities: a client that only shows windows does not need
#   WindowControl.
#
# The data follows the task model of KDE Plasma (libtaskmanager), which the service mirrors:
# the same window states, the same launcher URL form ("applications:org.kde.konsole.desktop").

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaWindows::Contract");

struct Rect {
  x @0 :Int32;
  y @1 :Int32;
  width @2 :UInt32;
  height @3 :UInt32;
}

# Bits of Window.states. The values are the ones of org_kde_plasma_window_management.state.
const stateActive :UInt32 = 0x1;
const stateMinimized :UInt32 = 0x2;
const stateMaximized :UInt32 = 0x4;
const stateFullscreen :UInt32 = 0x8;
const stateKeepAbove :UInt32 = 0x10;
const stateKeepBelow :UInt32 = 0x20;
const stateOnAllDesktops :UInt32 = 0x40;
const stateDemandsAttention :UInt32 = 0x80;
const stateCloseable :UInt32 = 0x100;
const stateMinimizable :UInt32 = 0x200;
const stateMaximizable :UInt32 = 0x400;
const stateFullscreenable :UInt32 = 0x800;
const stateSkipTaskbar :UInt32 = 0x1000;
const stateShadeable :UInt32 = 0x2000;
const stateShaded :UInt32 = 0x4000;
const stateMovable :UInt32 = 0x8000;
const stateResizable :UInt32 = 0x10000;
const stateVirtualDesktopChangeable :UInt32 = 0x20000;
const stateSkipSwitcher :UInt32 = 0x40000;

struct Window {
  id @0 :Text;                     # stable id (UUID from the compositor)
  title @1 :Text;
  appId @2 :Text;                  # the identified application: desktop entry id,
                                   # e.g. "org.kde.konsole.desktop"; empty when not identified
  rawAppId @3 :Text;               # app id reported by the window (Wayland app_id, X11 class)
  appName @4 :Text;                # Name= of the desktop entry, localized
  genericName @5 :Text;            # GenericName= of the desktop entry, localized
  iconName @6 :Text;               # theme icon name (desktop entry, or the one the window gave)
  iconSerial @7 :UInt32;           # > 0 when the compositor has a bitmap icon of the window;
                                   # a new value means a new icon, fetch it with WindowService.icon()
  launcherUrl @8 :Text;            # "applications:<desktop entry id>", empty when not identified
  pid @9 :UInt32;
  states @10 :UInt32;              # state* bits above
  geometry @11 :Rect;              # in absolute screen coordinates, with decorations
  virtualDesktops @12 :List(Text);
  parentId @13 :Text;              # parent window (e.g. of a dialog), empty for a top-level window
  lastActivated @14 :Int64;        # ms since 1970 when it was last activated, 0 = never
  canLaunchNewInstance @15 :Bool;  # the application can be started again (it has a desktop entry)
}

# Receiver of the window list.
# The messages about one window arrive in order (added, changed..., removed). Changes of one window
# come at most once per frame (~16 ms), with its latest state: a window being dragged changes its
# geometry on every frame. Messages about different windows may arrive in any order relative to
# each other.
interface WindowListener {
  snapshot @0 (windows :List(Window));   # the whole state, the first call after watch()
  added @1 (window :Window);
  changed @2 (window :Window);           # the whole window again (it is small)
  removed @3 (id :Text);
}

# Handle of a subscription: dropping it ends the subscription in the service
interface Subscription {}

# What the backend (the compositor) can do; bits of WindowService.info().capabilities
const capActivate :UInt32 = 0x1;
const capClose :UInt32 = 0x2;
const capMinimize :UInt32 = 0x4;
const capMaximize :UInt32 = 0x8;
const capFullscreen :UInt32 = 0x10;
const capKeepAboveBelow :UInt32 = 0x20;
const capMoveResize :UInt32 = 0x40;
const capVirtualDesktops :UInt32 = 0x80;
const capBitmapIcons :UInt32 = 0x100;
const capLaunch :UInt32 = 0x200;

interface WindowService {
  # Name of the backend (e.g. "kwin") and its capabilities
  info @0 () -> (backend :Text, capabilities :UInt32, serviceVersion :Text);

  # The window list: snapshot first, then changes, while the client keeps the subscription
  watch @1 (listener :WindowListener) -> (subscription :Subscription);

  # Control of the windows (a separate capability)
  control @2 () -> (control :WindowControl);

  # Bitmap icon of a window, when Window.iconSerial > 0. The data is what KWin sends:
  # a QIcon serialized with QDataStream (read it with QDataStream >> QIcon).
  icon @3 (id :Text) -> (data :Data, serial :UInt32);
}

interface WindowControl {
  activate @0 (id :Text);
  close @1 (id :Text);
  setMinimized @2 (id :Text, minimized :Bool);
  setMaximized @3 (id :Text, maximized :Bool);
  setFullscreen @4 (id :Text, fullscreen :Bool);
  setKeepAbove @5 (id :Text, keepAbove :Bool);
  setKeepBelow @6 (id :Text, keepBelow :Bool);
  requestMove @7 (id :Text);               # interactive move, done by the compositor
  requestResize @8 (id :Text);             # interactive resize, done by the compositor
  launchNewInstance @9 (id :Text);         # starts the application of the window again
  launch @10 (launcherUrl :Text);          # starts an application, e.g. "applications:org.kde.konsole.desktop"
}
