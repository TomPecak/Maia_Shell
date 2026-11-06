# Adding an area (icons, cursors, colors, ...)

An area is one kind of look. Decorations are the model; copy their shape.

1. **Contract**: `contract/<area>.capnp` with its values, a `<Area>Listener` (snapshot + changes)
   and an interface (`list`, `current`, `watch`, `set`, ...). Use `common.capnp` for Result,
   ErrorCode and Subscription. Add `<area> @N () -> (<area> :<Area>.<Area>)` to AppearanceService
   in `appearance.capnp` (a new number: existing clients keep working).
2. **Build**: add the file to `SCHEMAS` in `service/build.rs`, a `<area>_capnp` module in
   `service/src/lib.rs`, and the file to `maia_capnp_generate_cpp` in `qml/CMakeLists.txt`.
3. **The area**: `service/src/<area>/` without Cap'n Proto: values (`theme.rs` style), finding
   things on disk (`catalog.rs` style, blocking, run through spawn_blocking), and `mod.rs` with
   one change at a time (a tokio Mutex), events to subscribers, async functions only.
4. **The compositor's part**: if the compositor stores it (cursor size in kwinrc, ...), add
   methods to the `Compositor` trait in `service/src/compositor/mod.rs` and implement them in
   `kwin.rs` and `fake.rs`. If KDE stores it elsewhere (`kdeglobals` for icons and colors), the
   area writes it with kwriteconfig6 like `kwin.rs` does, and tells KDE apps (KGlobalSettings
   D-Bus signal `notifyChange`).
5. **RPC**: `service/src/rpc/<area>.rs` like `rpc/decorations.rs`; create it in
   `AppearanceService::client`.
6. **QML**: a model type like `WindowDecorations`, the client calls in `AppearanceConnection`
   (pipelined `service.<area>Request()`), the store in `AppearanceSource`, a test like
   `tests/tst_appearance.cpp`.
7. **Tests**: unit tests next to the code, a case in `service/tests/service.rs`.

Rules that keep it simple to change: no Cap'n Proto outside `rpc/` and `AppearanceConnection.cpp`;
nothing blocking on the service's thread; every change answered with a Result; errors are values,
never exceptions.
