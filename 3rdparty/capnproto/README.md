# Cap'n Proto (C++)

Serialization and RPC for the contracts between Maia services and their clients
(e.g. `Maia/services/windows/contract/windows.capnp`). The services are written in Rust and use the
Rust crates `capnp` / `capnp-rpc` (from cargo). The Qt side (QML modules such as `Maia.Windows`)
uses this C++ implementation. Both speak the same wire protocol, which is stable across versions.

| | |
|---|---|
| Version | 1.5.0 |
| Source | <https://capnproto.org/capnproto-c++-1.5.0.tar.gz> (the official C++ release archive) |
| SHA-256 | `77dbc13ca82d9c87ddb4581dd49559d45b63096433d3dadea08b7f31b360a5ba` |
| License | MIT, `upstream/LICENSE.txt` |
| Local changes | none |

Why it is built here: Ubuntu has only version 1.1, and installing a newer one by hand into
`/usr/local` would make every machine that builds or runs Maia need the same manual step.

## What is built

Only what Maia needs, as static, position-independent libraries without OpenSSL or zlib:

- libraries `kj`, `kj-async`, `capnp`, `capnp-rpc`, linked into the programs that use
  `Maia::CapnProto` (e.g. `appMaiaServer`);
- the schema compiler `capnp` and its C++ plugin `capnpc-c++`. They are used only during the
  build: to generate C++ code, and the Rust code in build.rs of the services.

Nothing of it is installed. The installed Maia has no Cap'n Proto files and no dependency on a
shared library.

## How Maia uses it

Only through these, never through the targets or paths of `upstream/`:

```cmake
include(MaiaCapnProto)

# C++: generated code + Maia::CapnProto for a target
maia_capnp_generate_cpp(MyModule
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/my.capnp)

# Rust: the compiler for build.rs (MAIA_CAPNP_EXECUTABLE, MAIA_CAPNP_IMPORT_DIR)
maia_capnp_cargo_environment(capnp_environment capnp_depends)
maia_add_cargo_executable(my-service MANIFEST ... ENVIRONMENT ${capnp_environment} DEPENDS ${capnp_depends})
```

Schemas are compiled with `--no-standard-import`. Only the standard schemas of this version
(`upstream/src/capnp/*.capnp`) are visible, never another version in `/usr/include` or
`/usr/local/include`.

## Installed Cap'n Proto instead (distribution packages)

```bash
cmake -DMAIA_USE_SYSTEM_CAPNPROTO=ON ...
```

This takes an installed Cap'n Proto 1.0 or newer (its CMake package `CapnProto`) with its own
compiler. The programs then depend on its shared libraries.

## Updating

1. Take the new version and the SHA-256 checksum of `capnproto-c++-<version>.tar.gz` from a trusted
   place: the release announcement or the GitHub release.
2. Run `./update.sh <version> <sha256>`. It downloads the archive, refuses it when the checksum
   differs, and replaces `upstream/`.
3. Update the table above (version, source, checksum) and the version in `3rdparty/README.md`.
4. Build from scratch and run `ctest`. Then test the services in a nested session.
