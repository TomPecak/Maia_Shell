# The session service (service/, Rust) and its QML module (qml/, Maia.Session); the contract
# between them is contract/session.capnp. See README.md.

include(MaiaRust)
include(MaiaCapnProto)

maia_capnp_cargo_environment(capnp_environment capnp_depends)

maia_add_cargo_executable(maia-session-service
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    # MAIA_VERSION: when the session script does not set it (~/.config/maia/<version>/, logs)
    ENVIRONMENT ${capnp_environment} MAIA_VERSION=${MAIA_VERSION}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
