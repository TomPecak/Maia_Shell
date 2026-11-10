@0xe3b8a1d26f4c9057;

# Contract of the Maia session service (maia.session, version 1).
#
# The service (service/, Rust, maia-session-service) is the main process of a Maia session: it
# starts the compositor, KDE's and Maia's services and the shell (appMaiaServer), starts them again
# after a crash, ends the session in order, and is the only process of Maia that talks to
# systemd-logind. Shells and apps (qml/, the Maia.Session QML module) read the state of the session
# and end it through this contract, over the Unix socket
#   $MAIA_SESSION_SOCKET
# which every process of the session gets in its environment (by default
# $XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock; a nested development session has its own).
#
# Rules:
# - watch() sends the whole state first (snapshot), then only changes, as long as the client keeps
#   the returned Subscription.
# - Nothing here blocks the session: logout(), reboot() and powerOff() answer once the request has
#   been accepted (reboot and powerOff after logind accepted it, which may mean the administrator's
#   password); what happens next arrives through the listener (state ending, children stopped).
# - Results that the user has to see are values (Result), not exceptions. A Cap'n Proto exception
#   means the call itself failed (service gone, bug).
# - Texts for people are not part of the contract: every frontend words states and errors itself.

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaSession::Contract");

enum ErrorCode {
  none @0;
  notAllowed @1;          # logind or polkit refused, or the user cancelled the authentication
  notSupported @2;        # the system cannot do it (e.g. hibernation without swap)
  busy @3;                # the session is starting or already ending
  notFound @4;            # no child of that name
  failed @5;              # anything else; Result.message has the detail (for logs)
}

struct Result {
  error @0 :ErrorCode;    # none = success
  message @1 :Text;       # technical detail for logs, not for the user interface
}

# What the system offers, from logind's Can* answers
enum Ability {
  no @0;                  # not possible ("no", "na")
  yes @1;
  challenge @2;           # possible after the administrator's password (polkit)
}

struct Capabilities {
  logout @0 :Bool;
  powerOff @1 :Ability;
  reboot @2 :Ability;
  suspend @3 :Ability;
  hibernate @4 :Ability;
  hybridSleep @5 :Ability;
  suspendThenHibernate @6 :Ability;
}

enum State {
  starting @0;            # the compositor and the services are being started
  running @1;
  ending @2;              # logout, reboot or power off is under way (Ending says which)
  sleeping @3;            # between logind's PrepareForSleep(true) and PrepareForSleep(false)
}

enum EndAction {
  logout @0;
  reboot @1;
  powerOff @2;
}

enum Initiator {
  user @0;                # logout(), reboot() or powerOff() of this contract
  system @1;              # SIGTERM, a shutdown from outside the session, or the compositor ended
}

struct Ending {
  action @0 :EndAction;
  initiator @1 :Initiator;
}

enum ChildKind {
  compositor @0;
  shell @1;               # appMaiaServer
  maiaService @2;
  kdeService @3;          # a systemd user unit of KDE (started, not watched: systemd watches it)
  helper @4;              # kglobalacceld, …
}

enum ChildState {
  waiting @0;             # not started yet
  running @1;
  restarting @2;          # ended unexpectedly, waits for its next start
  failed @3;              # given up after too many crashes, or could not be started
  stopped @4;             # ended on purpose
}

struct Child {
  name @0 :Text;          # as in session.toml: "appMaiaServer", "maia-network-service", …
  kind @1 :ChildKind;
  state @2 :ChildState;
  pid @3 :UInt32;         # 0 when not running
  restarts @4 :UInt32;    # since the session started
  lastExit @5 :Text;      # "exit code 1", "signal 11 (SIGSEGV)"; for logs and a debug page
}

struct Info {
  serviceVersion @0 :Text;
  maiaVersion @1 :Text;   # "0.2.0"
  compositor @2 :Text;    # the compositor entry of session.toml: "kwin", "wayfire", …
  sessionId @3 :Text;     # logind's session id ($XDG_SESSION_ID)
  backend @4 :Text;       # "logind", or "fake" (tests, nested sessions: nothing reaches the machine)
}

struct Variable {
  name @0 :Text;
  value @1 :Text;
}

interface SessionListener {
  snapshot @0 (state :State, ending :Ending, capabilities :Capabilities, children :List(Child));
  stateChanged @1 (state :State, ending :Ending);
  capabilitiesChanged @2 (capabilities :Capabilities);
  childChanged @3 (child :Child);
}

interface Subscription {}

interface SessionService {
  info @0 () -> (info :Info);
  watch @1 (listener :SessionListener) -> (subscription :Subscription);
  control @2 () -> (control :SessionControl);

  # Internal: called by `maia-session-service --compositor-ready`, which the compositor starts
  # once its display is up; environment carries WAYLAND_DISPLAY, DISPLAY, XAUTHORITY, …
  compositorReady @3 (environment :List(Variable)) -> ();
}

interface SessionControl {
  logout @0 () -> (result :Result);
  reboot @1 () -> (result :Result);
  powerOff @2 () -> (result :Result);
  suspend @3 () -> (result :Result);
  hibernate @4 () -> (result :Result);
  hybridSleep @5 () -> (result :Result);
  suspendThenHibernate @6 () -> (result :Result);

  # Starts a child again by hand (e.g. the shell, from a debug page); not systemd units
  restartChild @7 (name :Text) -> (result :Result);
}
