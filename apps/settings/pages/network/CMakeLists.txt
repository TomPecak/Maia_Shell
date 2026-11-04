# The Wi-Fi page of Maia Settings (docs: Maia/services/network/docs/gnome-wifi-features.md).
# Loaded from disk by the frame; installed as it is.

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION ${KDE_INSTALL_DATADIR}/maia-settings/pages/network
    PATTERN "CMakeLists.txt" EXCLUDE
)
