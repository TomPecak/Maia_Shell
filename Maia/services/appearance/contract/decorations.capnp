@0xb312c50788b63bb7;

# Window decorations: the theme of the window frames the compositor draws, and installing themes.
# Reached through AppearanceService.decorations() (appearance.capnp).
#
# A theme is named by an id "<engine>:<name>", the same on every compositor:
#
#   engine        what it is                                   KWin                     Wayfire (later)
#   aurorae-svg   Aurorae SVG theme (dir with metadata.desktop  library aurorae.v2       the wayfire-aurorae
#                 and decoration.svg), e.g. aurorae-svg:XBoomer                          plugin
#   aurorae-qml   Aurorae QML theme (KPackage KWin/Decoration)  library aurorae (v1)     no
#   kdecoration   native KDecoration3 plugin (Breeze, Oxygen),  library <plugin id>      no
#                 e.g. kdecoration:org.kde.breeze
#   wayfire       Wayfire's own decoration                      no                       yes
#
# Themes the running compositor cannot draw are listed with available = false and the reason, so
# a frontend can show them greyed out instead of pretending they do not exist.

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaAppearance::Contract");

using Common = import "common.capnp";

enum Engine {
  auroraeSvg @0;
  auroraeQml @1;
  kdecoration @2;
  wayfire @3;
}

enum Origin {
  system @0;              # installed by the distribution (/usr/share, the system plugin directory)
  maia @1;                # shipped with Maia or one of its frontends (<maia prefix>/share)
  user @2;                # installed by the user (~/.local/share); only these can be removed
}

enum BorderSize {
  theme @0;               # the size the theme recommends
  none @1;
  noSides @2;
  tiny @3;
  normal @4;
  large @5;
  veryLarge @6;
  huge @7;
  veryHuge @8;
  oversized @9;
}

struct Theme {
  id @0 :Text;            # "aurorae-svg:XBoomer"
  engine @1 :Engine;
  name @2 :Text;          # shown name, in the user's language when the theme has it
  description @3 :Text;
  author @4 :Text;
  origin @5 :Origin;
  available @6 :Bool;     # the running compositor can draw it
  unavailableReason @7 :Text;
  path @8 :Text;          # its directory or plugin file, for information
}

struct Current {
  themeId @0 :Text;       # what is chosen ("" when nothing is known yet)
  borderSize @1 :BorderSize;
  confirmed @2 :Bool;     # the compositor reported that it uses it
  frontend @3 :Text;      # the frontend whose choice this is ("" = none active)
}

struct Capabilities {
  compositor @0 :Text;    # "kwin", later "wayfire"
  engines @1 :List(Engine);   # the engines it can draw
  borderSizes @2 :Bool;   # setBorderSize works
  install @3 :Bool;       # install() works
}

interface DecorationsListener {
  # First call after watch(): everything
  snapshot @0 (themes :List(Theme), current :Current);
  # The list changed (a theme installed or removed, here or by another program); always the
  # whole list, it is short
  themesChanged @1 (themes :List(Theme));
  currentChanged @2 (current :Current);
}

# Held by a frontend's shell while it runs (FrontendLook in Maia.Appearance). Its release ends
# the frontend's turn: later choices are no longer remembered for it.
interface FrontendActivation {}

interface Decorations {
  capabilities @0 () -> (capabilities :Capabilities);
  list @1 () -> (themes :List(Theme));
  current @2 () -> (current :Current);
  watch @3 (listener :DecorationsListener) -> (subscription :Common.Subscription);

  # Uses the theme. Returns once the compositor took it (or with the reason it did not). While a
  # frontend is active the choice is remembered for that frontend.
  set @4 (themeId :Text) -> (result :Common.Result);
  setBorderSize @5 (size :BorderSize) -> (result :Common.Result);

  # Installs a theme for this user from a directory or an archive (.tar.gz, .tar.xz, .tar.zst,
  # .tar.bz2, .zip) given by its path. The archive is checked before anything is installed: one
  # theme, no links, no paths leaving it, limited size. Returns the new theme's id; nothing is
  # chosen. A name that is taken answers alreadyExists.
  install @6 (path :Text) -> (result :Common.Result, themeId :Text);
  # Removes a theme the user installed (origin user). The chosen theme cannot be removed.
  remove @7 (themeId :Text) -> (result :Common.Result);

  # A frontend's shell starts: its remembered choice is used, or, the first time, its default
  # (defaultThemeId; "" keeps what is chosen now and remembers that). The frontend stays active
  # while the client keeps the activation.
  activateFrontend @8 (frontend :Text, defaultThemeId :Text)
      -> (result :Common.Result, activation :FrontendActivation);

  # Looks for themes again (they are watched anyway; for a manual "refresh")
  refresh @9 () -> ();
}
