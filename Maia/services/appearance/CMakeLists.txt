# Maia appearance service: how the session looks (window decorations now; icons, cursors, colors
# later) for shells, Maia Settings and apps.
#
#   contract/   common.capnp, decorations.capnp, appearance.capnp: the Cap'n Proto contract
#   service/    maia-appearance-service (Rust): talks to the compositor (KWin), serves the contract
#   qml/        Maia.Appearance, the QML module (C++): WindowDecorations, FrontendLook
#   docs/       how to add an area or a compositor
#
# See README.md. Rust is built by cmake/MaiaRust.cmake (cargo), Cap'n Proto comes from
# 3rdparty/capnproto (cmake/MaiaCapnProto.cmake).

include(MaiaRust)
include(MaiaCapnProto)

# build.rs compiles the contract with the Cap'n Proto compiler of 3rdparty/capnproto
maia_capnp_cargo_environment(capnp_environment capnp_depends)

# Started by the session script, not by the user: libexec
maia_add_cargo_executable(maia-appearance-service
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    ENVIRONMENT ${capnp_environment}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
