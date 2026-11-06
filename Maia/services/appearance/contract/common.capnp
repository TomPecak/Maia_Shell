@0xdfd0f88b536a846e;

# Types shared by every area of the appearance service (decorations.capnp, later icons, cursors,
# colors). See appearance.capnp for the service itself.

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaAppearance::Contract");

enum ErrorCode {
  none @0;
  notFound @1;            # no such theme (or it is gone)
  notAllowed @2;          # e.g. removing a theme of the system
  invalidArgument @3;     # e.g. not a theme, a malformed archive, a bad id
  notSupported @4;        # the running compositor cannot use it
  unavailable @5;         # the compositor does not answer; the choice is saved and used when it does
  failed @6;              # the compositor did not take it (Result.message tells what it did instead)
  alreadyExists @7;       # installing a theme whose name is taken
}

# The answer of every call that changes something. message is for logs, not for the user.
struct Result {
  error @0 :ErrorCode;
  message @1 :Text;
}

# Held by a client for as long as it wants the calls of its listener (or its registration);
# releasing it, or losing the connection, ends them
interface Subscription {}
