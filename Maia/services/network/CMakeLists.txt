# Maia network service: Wi-Fi through NetworkManager for shells, Maia Settings and apps.
#
#   contract/   network.capnp, the Cap'n Proto contract between the service and its clients
#   service/    maia-network-service (Rust): talks to NetworkManager, serves the contract
#   qml/        Maia.Network, the QML module (C++): status, models and the password prompt
#   docs/       what the user interface offers (from GNOME), the reference for the contract
#
# See README.md. Rust is built by cmake/MaiaRust.cmake (cargo), Cap'n Proto comes from
# 3rdparty/capnproto (cmake/MaiaCapnProto.cmake).

include(MaiaRust)
include(MaiaCapnProto)

# build.rs compiles the contract with the Cap'n Proto compiler of 3rdparty/capnproto
maia_capnp_cargo_environment(capnp_environment capnp_depends)

# Started by the session script, not by the user: libexec
maia_add_cargo_executable(maia-network-service
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    ENVIRONMENT ${capnp_environment}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
