# (Twój poprzedni kod CMake pozostaje bez zmian, aż do momentu DeployScripts)

add_custom_target(DeployScripts)

# List the scripts to be installed (bez install_on_ubuntu.sh!)
set(RUN_SCRIPTS
    run_maia_nested_wayland.sh
    run_logger.sh
)

# KAZUJEMY CMAKE PODMIENIĆ ZMIENNE W SZABLONIE SKRYPTU BASH
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/install_on_ubuntu.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh
    @ONLY
)

configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/run_maia_wayland.sh.in
    ${CMAKE_CURRENT_BINARY_DIR}/run_maia_wayland.sh
    @ONLY
)


# Add the scripts as sources to the DeployScripts target
target_sources(DeployScripts
    PRIVATE ${RUN_SCRIPTS}
    PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh
    PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/run_maia_wayland.sh
)

add_custom_target(DeployScriptsTemplates)
target_sources(DeployScriptsTemplates
    PRIVATE install_on_ubuntu.sh.in
    PRIVATE run_maia_wayland.sh.in
)

# Install the RUN_SCRIPTS to the specified directory under CMAKE_INSTALL_PREFIX
install(FILES ${RUN_SCRIPTS} ${CMAKE_CURRENT_BINARY_DIR}/run_maia_wayland.sh
        DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)

# Domyślne ustawienia Mai dla komponentów KDE (np. wyłączony KDE Wallet); skrypty sesji dodają
# <prefix>/etc/xdg na końcu XDG_CONFIG_DIRS
install(DIRECTORY etc/ DESTINATION "${CMAKE_INSTALL_PREFIX}/etc")

# Install WYZGENEROWANY plik install_on_ubuntu.sh jedno piętro wyżej
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh
        DESTINATION "${CMAKE_INSTALL_PREFIX}/.."
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)
