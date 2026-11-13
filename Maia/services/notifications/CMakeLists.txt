# The notification service (service/, Rust) and its two QML modules (qml/): Maia.Notifications for
# programs that send notifications, Maia.Notifications.Center for shells that show them. The contract
# is contract/notifications.capnp. See README.md.

include(MaiaRust)
include(MaiaCapnProto)

maia_capnp_cargo_environment(capnp_environment capnp_depends)

maia_add_cargo_executable(maia-notifications-service
    MANIFEST ${CMAKE_CURRENT_SOURCE_DIR}/service/Cargo.toml
    INSTALL_DESTINATION "${CMAKE_INSTALL_PREFIX}/libexec"
    ENVIRONMENT ${capnp_environment}
    DEPENDS ${capnp_depends}
)

add_subdirectory(qml)
