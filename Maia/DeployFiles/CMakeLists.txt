# Define the DeployScripts target
add_custom_target(DeployScripts)

# List the scripts to be installed
set(RUN_SCRIPTS
    run.sh
    run_maia_in_xephyr.sh
    run_logger.sh
)

set(INST_SCRIPT
    install_on_ubuntu.sh
)

# Add the scripts as sources to the DeployScripts target (optional, for clarity)
target_sources(DeployScripts
    PRIVATE ${RUN_SCRIPTS}
    PRIVATE ${INST_SCRIPT}
)

# Install the scripts to the specified directory under CMAKE_INSTALL_PREFIX
install(FILES ${RUN_SCRIPTS}
        DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)

install(FILES ${INST_SCRIPT}
        DESTINATION "${CMAKE_INSTALL_PREFIX}/.."
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)
