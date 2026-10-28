# External dependencies

Libraries that Maia builds itself instead of expecting them on the system. Usually because the
distributions ship an old version or none at all. A clone of the repository builds with no manual
installation, and the installed Maia does not depend on them (they are linked statically).

| Dependency | Version | Used for | Maia name |
|---|---|---|---|
| [Cap'n Proto](capnproto/README.md) (C++) | 1.5.0 | contracts between services and their clients | `Maia::CapnProto`, `cmake/MaiaCapnProto.cmake` |

Rust crates are not here: cargo fetches and pins them (`Cargo.lock`).

## Layout of a dependency

```text
3rdparty/<name>/
  upstream/        the source of an official release, exactly as published: never edited
  CMakeLists.txt   builds upstream/ for Maia and publishes it under a Maia name (Maia::<Name>)
  README.md        what it is, why Maia needs it, version, origin, checksum, license, how to update
  update.sh        replaces upstream/ with another release, verifying its checksum
```

## Rules

- **upstream/ stays unchanged.** Then an update is mechanical (`update.sh`) and the code can be
  compared with the release at any time. If a change is unavoidable, keep it as a patch file next to
  upstream/ and apply it in `update.sh`, with the reason in the README.
- **Maia code uses only the Maia name** (`Maia::CapnProto`, the functions in `cmake/`), never the
  targets of the dependency or the paths in upstream/. Whether the dependency is built here or comes
  from the system is decided in one place: its `CMakeLists.txt`.
- **Built the way its authors build it.** `3rdparty/CMakeLists.txt` undoes Maia's (KDE's) compiler
  settings for this directory: exceptions on, warnings off. It also builds static and
  position-independent code, without the dependency's tests.
- **Nothing of it is installed.** The dependencies are added with `EXCLUDE_FROM_ALL`. Only the
  targets Maia uses get built, and their install rules do not run on `cmake --install`.
- **The system version is an option, not the default.** `MAIA_USE_SYSTEM_<NAME>=ON` takes an
  installed version instead, for distribution packages that must use the system libraries.

## Adding a dependency

1. Check that it is really needed, and that it is not a Rust crate (cargo) or a Qt/KDE package.
2. Create `3rdparty/<name>/` as above, with `upstream/` from an official release archive. Write
   its address and SHA-256 checksum into the README.
3. Publish a `Maia::<Name>` target and add the directory in `3rdparty/CMakeLists.txt`.
4. Check that `cmake --install` installs nothing of it, and that `ldd` of the programs shows no
   new library.
