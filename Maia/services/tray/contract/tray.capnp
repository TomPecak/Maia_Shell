@0xcabcb6e983a5badb;

# Contract of the Maia tray service (maia.tray, version 1).
#
# The service (service/, Rust, maia-tray-service) is the system tray of a Maia session. Applications
# show their icons the way they do on every Linux desktop: StatusNotifierItem over D-Bus (KDE's
# specification, used by Qt, KDE, GTK through libayatana-appindicator, Electron, Chromium). The
# service is both sides of it:
#   - the watcher (org.kde.StatusNotifierWatcher): applications register their items with it;
#   - the only host: it reads the items, their menus (com.canonical.dbusmenu) and their images, and
#     gives them to the shells through this contract.
# Old X11 icons (XEmbed: Wine, old GTK2 and Java programs) come through KDE's xembedsniproxy, which
# turns each into an item.
#
# Socket: $XDG_RUNTIME_DIR/maia/tray-$WAYLAND_DISPLAY.sock (TrayHost, for shells).
# QML: Maia.Tray (qml/).
#
# Rules:
# - An item is identified by its id (UInt32, never 0), given by the service when the application
#   registers it. Ids grow: sorting by id is the order of registration.
# - watch() sends all items first (snapshot), then the changes, in batches, at most one per frame
#   (16 ms). A batch is applied as a whole. An item is sent once its properties are read; one whose
#   application does not answer is never shown.
# - Only data: titles and tool tips are the application's own texts (plain text), the shell decides
#   how they look and which items it shows where (by status and category).
# - Images are file:// URLs. Pixels sent over D-Bus (IconPixmap, icon-data of a menu entry) are
#   written as PNG (at most 64 px for icons) into $XDG_RUNTIME_DIR/maia/tray-$WAYLAND_DISPLAY/,
#   which lives in memory; the name of a file is its content, so a new image is a new URL and the
#   same image (an animation's frames, a menu opened again) is written once.
# - Nothing waits for an application: the service reads it in the background with a time limit, and
#   a click is passed on without waiting for the application's answer.

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaTray::Contract");

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------

enum ErrorCode {
  none @0;
  notFound @1;            # no such item or menu entry (any more)
  invalidArgument @2;     # e.g. openMenu() of an item without a menu
  unavailable @3;         # the application does not answer, or the service is ending
}

struct Result {
  error @0 :ErrorCode;    # none = success
  message @1 :Text;       # technical detail for logs, not for the user interface
}

# ---------------------------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------------------------

enum Status {
  passive @0;             # nothing to see: may go into the overflow (a mail client without mail)
  active @1;              # in the tray
  needsAttention @2;      # wants the user (a new message): shown, with attentionIcon when it has one
}

enum Category {
  applicationStatus @0;   # an application's own (a music player, a chat)
  communications @1;      # mail, chat, phone
  systemServices @2;      # the system (updates, backups)
  hardware @3;            # devices (battery, Bluetooth, network applets)
}

enum Orientation {
  vertical @0;            # the usual wheel
  horizontal @1;
}

struct Icon {
  name @0 :Text;          # an icon name of the shell's icon theme, "" none
  url @1 :Text;           # file:// URL of the same icon as an image (the application's pixels, or the
                          # file of its own icon directory), "" none. With both: the theme's icon
                          # when the theme has it, otherwise the image
  mask @2 :Bool;          # the image is one grey on transparency (a "template", as macOS has them,
                          # made for a light or a dark panel): the shell draws its shape in its own
                          # colour of text. Only images given as pixels are looked at
}

struct ToolTip {
  title @0 :Text;
  text @1 :Text;          # plain text, may have several lines
  icon @2 :Icon;
}

struct Item {
  id @0 :UInt32;
  key @1 :Text;           # stays the same across restarts of the application (its item's Id, or its
                          # desktop entry): for what a shell or the user remembers about an item
  title @2 :Text;         # the application's name for it ("Telegram"), may be ""
  status @3 :Status;
  category @4 :Category;
  icon @5 :Icon;
  attentionIcon @6 :Icon; # for needsAttention, when the application has one
  overlayIcon @7 :Icon;   # a small sign drawn over the icon (an unread count), when it has one
  toolTip @8 :ToolTip;
  hasMenu @9 :Bool;       # openMenu() gives its menu
  itemIsMenu @10 :Bool;   # it only has a menu: a primary click opens it instead of activate()
  desktopEntry @11 :Text; # the application's desktop entry id ("org.telegram.desktop"), "" unknown
  appName @12 :Text;      # the name its desktop entry gives, or the title
  appIcon @13 :Text;      # the icon its desktop entry gives (a name or a file:// URL), "" unknown
}

interface TrayListener {
  snapshot @0 (items :List(Item));                          # everything, in the order of ids
  changes @1 (changed :List(Item), removed :List(UInt32));  # new and changed items, gone ones
}

interface Subscription {}                 # dropping it stops the listener

# ---------------------------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------------------------

enum Toggle {
  none @0;
  checkmark @1;           # on or off on its own
  radio @2;               # one of a group (the entries between two separators)
}

struct MenuEntry {
  id @0 :Int32;           # for activate() and aboutToShow(); 0 is the menu itself
  separator @1 :Bool;     # a line between groups, nothing else of it counts
  label @2 :Text;         # mnemonics removed ("_Quit" → "Quit")
  enabled @3 :Bool;
  icon @4 :Icon;
  toggle @5 :Toggle;
  checked @6 :Bool;       # with a toggle
  shortcut @7 :Text;      # how the application names its key ("Ctrl+Q"), "" none
  submenu @8 :Bool;       # opens the entries in children; they may arrive only after aboutToShow()
  children @9 :List(MenuEntry);
}
# Entries the application hides are left out.

interface MenuListener {
  layout @0 (entries :List(MenuEntry));   # the whole menu: at openMenu(), then after every change
  closed @1 ();                           # the item went away: the shell closes the menu
}

interface Menu {
  # A submenu opens or closes (the application may fill it now: a new layout() follows)
  aboutToShow @0 (entryId :Int32) -> ();
  submenuClosed @1 (entryId :Int32) -> ();
  # The user picked the entry. The token is an xdg-activation token for the window the entry may
  # raise ("" none). The shell closes the menu afterwards.
  activate @2 (entryId :Int32, activationToken :Text) -> (result :Result);
}
# Dropping the Menu closes it for the application (com.canonical.dbusmenu "closed").

# ---------------------------------------------------------------------------------------------
# The shells
# ---------------------------------------------------------------------------------------------

interface TrayHost {
  info @0 () -> (serviceVersion :Text);
  watch @1 (listener :TrayListener) -> (subscription :Subscription);

  # A primary click (or a tap). x, y: where, in global coordinates, if the shell knows (0, 0
  # otherwise); Wayland applications ignore them. The token raises the application's window.
  activate @2 (id :UInt32, x :Int32, y :Int32, activationToken :Text) -> (result :Result);
  # A middle click
  secondaryActivate @3 (id :UInt32, x :Int32, y :Int32, activationToken :Text) -> (result :Result);
  # The application shows its own menu (an item without hasMenu)
  contextMenu @4 (id :UInt32, x :Int32, y :Int32) -> (result :Result);
  # The wheel: delta in steps of 120 per notch
  scroll @5 (id :UInt32, delta :Int32, orientation :Orientation) -> (result :Result);

  # Opens the item's menu; its entries come to the listener (layout()) as long as the shell keeps
  # the Menu
  openMenu @6 (id :UInt32, listener :MenuListener) -> (menu :Menu, result :Result);
}
