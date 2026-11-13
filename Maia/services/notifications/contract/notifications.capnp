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
# QML: Maia.Notifications (senders) and Maia.Notifications.Center (shells), qml/.
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
# - Jobs (the progress of a copy in Dolphin, of an archive, a download) come from KDE's
#   org.kde.JobViewServer on D-Bus and are a second list next to the notifications: shown 0.5 s
#   after they start (a short job never flickers), updated at most every 250 ms, and kept when they
#   end (finished or failed) until dismissed; a job the user canceled goes at once.

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

# ---------------------------------------------------------------------------------------------
# Jobs (org.kde.JobViewServer)
# ---------------------------------------------------------------------------------------------

enum JobState {
  running @0;
  suspended @1;           # paused (by the user, through suspendJob)
  finished @2;            # ended well
  failed @3;              # ended with an error (errorText), or its application quit (ownerGone)
}

struct JobField {         # a line of details the application gives: ("Source", "/home/a/x.iso")
  label @0 :Text;
  value @1 :Text;
}

struct Job {
  id @0 :UInt32;          # its own numbering, not that of notifications
  appName @1 :Text;
  desktopEntry @2 :Text;
  appIcon @3 :Text;       # a theme icon name, "" none
  title @4 :Text;         # what it does ("Copying"), from the application
  infoMessage @5 :Text;   # the current step ("Copying photo.jpg"), from the application
  state @6 :JobState;
  percent @7 :Int32;      # 0 .. 100, -1 unknown
  processedBytes @8 :UInt64;
  totalBytes @9 :UInt64;  # 0 = unknown, likewise for the other amounts
  processedFiles @10 :UInt64;
  totalFiles @11 :UInt64;
  processedDirectories @12 :UInt64;
  totalDirectories @13 :UInt64;
  processedItems @14 :UInt64;
  totalItems @15 :UInt64;
  speed @16 :UInt64;      # bytes per second, 0 unknown
  elapsed @17 :Int64;     # ms the application reports it has been working, 0 unknown
  fields @18 :List(JobField);
  destination @19 :Text;  # where the result is (a URL, e.g. file:///home/a/Pictures), "" unknown
  errorCode @20 :UInt32;  # the application's (KIO's) code, 0 none
  errorText @21 :Text;    # the application's description of the error, "" none
  ownerGone @22 :Bool;    # failed because its application quit
  killable @23 :Bool;     # cancelJob works
  suspendable @24 :Bool;  # suspendJob works
  started @25 :Int64;     # ms since 1970
  updated @26 :Int64;     # ms since 1970, the last change
}

struct Snapshot {
  notifications @0 :List(Notification);   # the newest first
  doNotDisturb @1 :DoNotDisturb;
  jobs @2 :List(Job);                     # the newest first
}

# ---------------------------------------------------------------------------------------------
# The shell: NotificationCenter
# ---------------------------------------------------------------------------------------------

interface CenterListener {
  snapshot @0 (snapshot :Snapshot);       # the whole state, the first call after watch()
  changes @1 (changed :List(Notification), removed :List(UInt32));
                                           # one batch: new or changed (same id), and removed
  doNotDisturbChanged @2 (doNotDisturb :DoNotDisturb);
  jobsChanged @3 (changed :List(Job), removed :List(UInt32));
                                           # one batch of jobs, like changes()
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

  # Jobs: the application is asked (cancel: it ends the job; one that does not within 2 s is
  # ended by the service)
  cancelJob @8 (id :UInt32) -> (result :Result);
  suspendJob @9 (id :UInt32, suspended :Bool) -> (result :Result);
  # A finished or failed job leaves the list
  dismissJob @10 (id :UInt32) -> (result :Result);
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
