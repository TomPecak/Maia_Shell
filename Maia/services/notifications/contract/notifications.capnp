@0xf9ffe624056b86e1;

# Contract of the Maia notification service (maia.notifications, version 1).
#
# The service (service/, Rust, maia-notifications-service) is the notification server of a Maia
# session. Applications reach it in two ways, and both end up in the same list:
#   - D-Bus, for every existing application: org.freedesktop.Notifications (the freedesktop.org
#     Desktop Notifications specification, with KDE's extensions: inline replies, inhibitions);
#   - this contract, for Maia's own programs and services: the Notifier.
# The shell shows the list through the NotificationCenter. Two sockets, one per role:
#   $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY.sock          Notifier (any program)
#   $XDG_RUNTIME_DIR/maia/notifications-center-$WAYLAND_DISPLAY.sock   NotificationCenter (the shell)
# The center sees the content of every notification (messages, codes), a sender only its own: a
# sandbox can later be given the first socket and not the second.
#
# QML: Maia.Notifications (senders) and Maia.NotificationCenter (shells), qml/.
#
# Rules:
# - A notification is identified by its id (UInt32, never 0), the one D-Bus clients get too.
# - watch() sends the whole list first (snapshot), then the changes. Changes are sent in batches,
#   at most one per frame (16 ms): a flood of notifications costs the shell one model update per
#   frame, not one per notification. A batch is applied as a whole.
# - Only data: the texts are the senders' own (a notification is a message for people), the shell
#   decides how it looks. The body is a safe subset of HTML (see Notification.body).
# - Images are file:// URLs: pixels sent over D-Bus are written as PNG (at most 512 px) into
#   $XDG_RUNTIME_DIR/maia/notifications-$WAYLAND_DISPLAY/, which lives in memory. A new image gets a
#   new URL, so a shell never shows a stale cached one.
# - The popup time is counted by the shell (it pauses while hovered); the shell reports the end with
#   expire(). Notifications stay in the list after their popup (the server has "persistence")
#   unless they are transient.
# - Nothing is kept on disk: the list lives as long as the session, across restarts of the shell.
# - Nothing here blocks: notify() answers at once; an image is prepared in the background and the
#   notification is shown when it is ready.

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaNotifications::Contract");

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------

enum ErrorCode {
  none @0;
  notFound @1;            # no such notification (any more)
  invalidArgument @2;     # e.g. an action key the notification does not have
  unavailable @3;         # the sender is gone (its connection to the bus or to us ended)
}

struct Result {
  error @0 :ErrorCode;    # none = success
  message @1 :Text;       # technical detail for logs, not for the user interface
}

# ---------------------------------------------------------------------------------------------
# A notification
# ---------------------------------------------------------------------------------------------

enum Urgency {            # normal first: it is the default of a request that does not set one
  normal @0;
  low @1;                 # e.g. "the battery is charged": into the list, without a popup
  critical @2;            # e.g. "the battery is empty": shown even with do not disturb, stays
}

enum CloseReason {        # the numbers + 1 are those of NotificationClosed in the specification
  expired @0;             # its time ran out (transient notifications only)
  dismissed @1;           # the user closed it, or used one of its actions
  closedByApp @2;         # its sender closed it
  other @3;               # e.g. dropped because the list was full
}

struct Action {
  key @0 :Text;           # sent back to the sender; "default" = a click on the notification itself
  label @1 :Text;         # the button's text ("" for "default"); an icon name with actionIcons
}

struct Notification {
  id @0 :UInt32;
  appName @1 :Text;       # the name the sender gives ("Thunderbird"); x-kde-display-appname wins
  desktopEntry @2 :Text;  # the application's desktop entry id ("org.mozilla.Thunderbird"), "" unknown
  appIcon @3 :Text;       # an icon name of the icon theme, or a file:// URL; "" none
  summary @4 :Text;       # the title, plain text
  body @5 :Text;          # a safe subset of HTML: <b> <i> <u> <a href="…"> <br/>, entities;
                          # everything else is text (Qt's StyledText shows it as it is)
  image @6 :Text;         # file:// URL of a picture to show (a photo, a cover), "" none
  actions @7 :List(Action);
  actionIcons @8 :Bool;   # the actions' labels are icon names (e.g. a media player's buttons)
  urgency @9 :Urgency;
  category @10 :Text;     # "email.arrived", "im.received", "device.added", …; "" none
  timeout @11 :Int32;     # ms of the popup: -1 = the shell decides, 0 = until the user closes it
  time @12 :Int64;        # when it was sent or last replaced, ms since 1970
  transient @13 :Bool;    # gone after its popup, not kept in the list
  resident @14 :Bool;     # stays after one of its actions
  popup @15 :Bool;        # to be shown as a popup: false when it came during do not disturb (not
                          # critical) or is low urgency; it is in the list either way
  expired @16 :Bool;      # its popup has ended (expire()); it stays in the list
  inlineReply @17 :Bool;  # offers a text field: the text goes back with reply() (KDE extension)
  replyPlaceholder @18 :Text;   # the field's hint ("Reply to Anna…"), "" default
  replySubmitText @19 :Text;    # the send button's text, "" default
  originName @20 :Text;   # where it really comes from, e.g. a phone through KDE Connect
  urls @21 :List(Text);   # files it is about (x-kde-urls), e.g. a screenshot
  soundName @22 :Text;    # a sound of the sound theme ("message-new-instant"), "" none
  soundFile @23 :Text;    # file:// URL of a sound file, "" none
  suppressSound @24 :Bool;
}

# ---------------------------------------------------------------------------------------------
# Do not disturb
# ---------------------------------------------------------------------------------------------

struct Inhibitor {        # an application that asked for quiet (KDE's Inhibit), e.g. a presentation
  desktopEntry @0 :Text;
  appName @1 :Text;
  reason @2 :Text;
}

struct DoNotDisturb {
  enabled @0 :Bool;       # the user's choice
  until @1 :Int64;        # ms since 1970 when the user's choice ends by itself, 0 = until turned off
  inhibitors @2 :List(Inhibitor);
  active @3 :Bool;        # quiet now: enabled or any inhibitor
}

struct Snapshot {
  notifications @0 :List(Notification);   # the newest first
  doNotDisturb @1 :DoNotDisturb;
}

# ---------------------------------------------------------------------------------------------
# The shell: NotificationCenter
# ---------------------------------------------------------------------------------------------

interface CenterListener {
  snapshot @0 (snapshot :Snapshot);       # the whole state, the first call after watch()
  changes @1 (changed :List(Notification), removed :List(UInt32));
                                           # one batch: new or changed (same id), and removed
  doNotDisturbChanged @2 (doNotDisturb :DoNotDisturb);
}

interface Subscription {}                 # dropping it stops the listener

interface NotificationCenter {
  info @0 () -> (serviceVersion :Text, capabilities :List(Text));
  watch @1 (listener :CenterListener) -> (subscription :Subscription);

  # The user used an action. activationToken is an xdg-activation token the shell got from the
  # compositor for the click, so that the application may raise its window ("" none).
  invokeAction @2 (id :UInt32, key :Text, activationToken :Text) -> (result :Result);
  # The text of the inline reply field
  reply @3 (id :UInt32, text :Text, activationToken :Text) -> (result :Result);
  # The user closed it
  dismiss @4 (id :UInt32) -> (result :Result);
  # Its popup has ended (the shell counts the time); transient notifications go
  expire @5 (id :UInt32) -> (result :Result);
  # "Clear all": every notification except critical ones
  dismissAll @6 () -> ();
  # until: ms since 1970, 0 = until turned off
  setDoNotDisturb @7 (enabled :Bool, until :Int64) -> ();
}

# ---------------------------------------------------------------------------------------------
# Senders: Notifier
# ---------------------------------------------------------------------------------------------

struct NotificationRequest {
  appName @0 :Text;
  desktopEntry @1 :Text;
  appIcon @2 :Text;       # an icon name, an absolute path or a file:// URL
  summary @3 :Text;
  body @4 :Text;          # the same subset of HTML as Notification.body
  image @5 :Text;         # an absolute path or a file:// URL, "" none
  actions @6 :List(Action);
  actionIcons @7 :Bool;
  urgency @8 :Urgency;
  category @9 :Text;
  timeout @10 :Int32;     # -1 the shell decides, 0 until closed, else ms
  transient @11 :Bool;
  resident @12 :Bool;
  inlineReply @13 :Bool;
  replyPlaceholder @14 :Text;
  replySubmitText @15 :Text;
  soundName @16 :Text;
  suppressSound @17 :Bool;
}

# What happens to the sender's notification: only the sender hears it (unlike D-Bus signals)
interface NotifierListener {
  actionInvoked @0 (key :Text, activationToken :Text);
  replied @1 (text :Text, activationToken :Text);
  closed @2 (reason :CloseReason);
}

# The sender's hold on one notification. Dropping it leaves the notification as it is.
interface NotificationHandle {
  update @0 (notification :NotificationRequest) -> (result :Result);   # replaces its content
  close @1 () -> ();
}

interface Notifier {
  info @0 () -> (serviceVersion :Text, capabilities :List(Text));
  notify @1 (notification :NotificationRequest, listener :NotifierListener)
         -> (id :UInt32, handle :NotificationHandle);
}
