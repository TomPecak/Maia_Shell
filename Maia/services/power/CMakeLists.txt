# The power service (service/, Rust) and its QML module (qml/, Maia.Power); the contract between
# them is contract/power.capnp. See README.md.

include(MaiaRust)
include(MaiaCapnProto)

maia_capnp_cargo_environment(capnp_environment capnp_depends)

maia_add_cargo_executable(maia-power-service
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    ENVIRONMENT ${capnp_environment}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
