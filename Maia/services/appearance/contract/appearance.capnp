@0xb27d14cda6430f7b;

# Contract of the Maia appearance service (maia.appearance, version 1).
#
# The service (service/, Rust, maia-appearance-service) is the one place of a Maia session that
# knows how the compositor stores its look (KWin: kwinrc and its D-Bus; later Wayfire). Shells,
# Maia Settings and apps (qml/, the Maia.Appearance QML module) only use this contract, over
#   $XDG_RUNTIME_DIR/maia/appearance-$WAYLAND_DISPLAY.sock
#
# One interface per area, each in its own file, reached from AppearanceService:
#   decorations.capnp   window decorations (now)
#   later: icons, cursors, colors, ... (new files, new methods here; existing ones stay)

using Cxx = import "/capnp/c++.capnp";
$Cxx.namespace("MaiaAppearance::Contract");

using Decorations = import "decorations.capnp";

interface AppearanceService {
  # backend: "kwin", or "fake" for tests; compositor: what runs
  info @0 () -> (backend :Text, compositor :Text, serviceVersion :Text);

  decorations @1 () -> (decorations :Decorations.Decorations);
}
