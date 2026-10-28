# Maia window service: the window list of the compositor for shells and apps.
#
#   contract/   windows.capnp, the Cap'n Proto contract between the two parts below
#   service/    maia-windows, the service (Rust): talks to KWin, serves the contract
#   qml/        Maia.Windows, the QML module (C++): TasksModel for taskbars and docks
#
# See README.md. Rust is built by cmake/MaiaRust.cmake (cargo), Cap'n Proto comes from
# 3rdparty/capnproto (cmake/MaiaCapnProto.cmake).

include(MaiaRust)
include(MaiaCapnProto)

# build.rs compiles the contract with the Cap'n Proto compiler of 3rdparty/capnproto
maia_capnp_cargo_environment(capnp_environment capnp_depends)

# Started by the session script, not by the user: libexec
maia_add_cargo_executable(maia-windows
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    ENVIRONMENT ${capnp_environment}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
