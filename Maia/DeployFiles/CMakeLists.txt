# What a Maia installation needs besides the programs: the sessions of SDDM, their scripts, the
# default settings (etc/) and the installer (install_on_ubuntu.sh, one level above the prefix).
#
# Sessions (session/, see maia-session-common.sh.in):
#   Maia <version> (KWin)     maia_<version>-kwin.desktop     bin/run_maia_kwin.sh
#   Maia <version> (Wayfire)  maia_<version>-wayfire.desktop  bin/run_maia_wayfire.sh
#                             etc/maia/wayfire.ini: the template of ~/.config/maia/<version>/wayfire.ini

add_custom_target(DeployScripts)

# Installed as they are
set(RUN_SCRIPTS
    run_maia_nested_wayland.sh
    run_logger.sh
)

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/install_on_ubuntu.sh.in ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh @ONLY)

# The session scripts and files of SDDM, with the version filled in
set(SESSION_SCRIPTS maia-session-common.sh run_maia_kwin.sh run_maia_wayfire.sh)
set(SESSION_FILES maia_${MAIA_VERSION}-kwin.desktop maia_${MAIA_VERSION}-wayfire.desktop)
set(session_outputs "")
foreach(script IN LISTS SESSION_SCRIPTS)
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/session/${script}.in ${CMAKE_CURRENT_BINARY_DIR}/${script} @ONLY)
    list(APPEND session_outputs ${CMAKE_CURRENT_BINARY_DIR}/${script})
endforeach()
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/session/maia-kwin.desktop.in
    ${CMAKE_CURRENT_BINARY_DIR}/maia_${MAIA_VERSION}-kwin.desktop @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/session/maia-wayfire.desktop.in
    ${CMAKE_CURRENT_BINARY_DIR}/maia_${MAIA_VERSION}-wayfire.desktop @ONLY)

target_sources(DeployScripts
    PRIVATE ${RUN_SCRIPTS}
    PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh
    PRIVATE ${session_outputs}
)

add_custom_target(DeployScriptsTemplates)
target_sources(DeployScriptsTemplates
    PRIVATE install_on_ubuntu.sh.in
    PRIVATE session/maia-session-common.sh.in
    PRIVATE session/run_maia_kwin.sh.in
    PRIVATE session/run_maia_wayfire.sh.in
    PRIVATE session/maia-kwin.desktop.in
    PRIVATE session/maia-wayfire.desktop.in
    PRIVATE etc/maia/wayfire.ini
)

install(FILES ${RUN_SCRIPTS} ${session_outputs}
        DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)

# The session files; install_on_ubuntu.sh copies them to /usr/share/wayland-sessions
list(TRANSFORM SESSION_FILES PREPEND "${CMAKE_CURRENT_BINARY_DIR}/")
install(FILES ${SESSION_FILES}
        DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
        PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
)

# Default settings of Maia: etc/xdg for KDE components (e.g. KDE Wallet off; the session scripts add
# <prefix>/etc/xdg at the end of XDG_CONFIG_DIRS) and etc/maia/wayfire.ini for the Wayfire session
install(DIRECTORY etc/ DESTINATION "${CMAKE_INSTALL_PREFIX}/etc")

# Install WYZGENEROWANY plik install_on_ubuntu.sh jedno piętro wyżej
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/install_on_ubuntu.sh
        DESTINATION "${CMAKE_INSTALL_PREFIX}/.."
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)
