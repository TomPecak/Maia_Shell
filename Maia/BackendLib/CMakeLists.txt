project(MaiaBackend VERSION ${MAIA_VERSION})

set(PROJECT_URI Maia.Backend)
#set(QML_IMPORT_PATH "${CMAKE_CURRENT_BINARY_DIR}")

include(GenerateExportHeader)
include(CMakePackageConfigHelpers)
include(ECMGenerateHeaders)
include(ECMFindQmlModule)
include(ECMQmlModule)
include(FindPkgConfig)
include(KDEInstallDirs)
include(KDECMakeSettings)

# Generate maia_version.h file with version #definitions.
# The file will be generated in the build directory.
ecm_setup_version(${MAIA_VERSION}
    VARIABLE_PREFIX MAIA
    VERSION_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/maia_version.h"
    PACKAGE_VERSION_FILE "${CMAKE_CURRENT_BINARY_DIR}/MaiaConfigVersion.cmake"
    SOVERSION ${PROJECT_VERSION_MAJOR}
)

find_package(
    Qt6 ${REQUIRED_QT_VERSION}
    REQUIRED
    NO_MODULE
    COMPONENTS
        Core
        Gui
        Quick
        DBus
        Concurrent
        Scxml
        WebEngineQuick
)

find_package(
    KF6 ${REQUIRED_KF_VERSION}
    REQUIRED
    COMPONENTS
        Config
        WindowSystem
)

find_package(
    KF6PulseAudioQt ${REQUIRED_PULSEAUDIOQT_VERSION}
    REQUIRED
)

# Generate cmake_config.h with CMAKE_INSTALL_PREFIX.
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake_config.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/cmake_config.h
)

qt_add_qml_module(${PROJECT_NAME}
    URI ${PROJECT_URI}
    VERSION 1.0

    SOURCES
        Backend.hpp
        Backend.cpp
        AppsListModel.hpp
        AppsListModel.cpp

        BackendAppsIconsProvider.hpp

        TaskbarIconProvider.hpp
        TaskbarIconProvider.cpp

        MAudioBackend.hpp
        MAudioBackend.cpp

        helper/Process.hpp
        helper/Process.cpp

        private/Mask.hpp
        private/Mask.cpp

        MMaskedItem.hpp
        MMaskedItem.cpp

        private/MaskAlgorithm.hpp
        private/MaskAlgorithm.cpp

        private/MaskTracker.hpp
        private/MaskTracker.cpp

        strut/Strut.hpp
        strut/StrutManager.hpp
        strut/StrutManager.cpp

        MSessionManager.hpp
        MSessionManager.cpp

        server/SessionService.hpp
        server/SessionService.cpp

        server/Server.hpp
        server/Server.cpp

        MTaskbarModel.hpp
        MTaskbarModel.cpp

        MTaskbarBaseModel.hpp
        MTaskbarBaseModel.cpp

        MFrontendModel.hpp
        MFrontendModel.cpp

        server/FrontendManagerService.hpp
        server/FrontendManagerService.cpp

        private/ProxyWindowServer.cpp
        private/ProxyWindowServer.hpp

        server/X11WindowManagerService.hpp
        server/X11WindowManagerService.cpp

        MWindowManagerX11.hpp
        MWindowManagerX11.cpp

        server/QmlGui.hpp
        server/QmlGui.cpp

        server/GuiManager.hpp
        server/GuiManager.cpp

        client/private/ProxyWindowController.hpp
        client/private/ProxyWindowController.cpp

        MProxyWindow.hpp
        MProxyWindow.cpp

        server/FavoriteAppsService.hpp
        server/FavoriteAppsService.cpp

        server/Application.hpp
        server/Application.cpp

        MFavoritesAppsModel.hpp
        MFavoritesAppsModel.cpp

        server/FavoriteAppsListModel.hpp

        audio/MPreferredDevice.hpp
        audio/MPreferredDevice.cpp

        server/FrontendInfo.hpp

        cmake_config.h.in

        MIconItem.hpp
        MIconItem.cpp

        cutefish/dock/applicationmodel.h
        cutefish/dock/applicationmodel.cpp
        cutefish/dock/applicationitem.h

        cutefish/dock/systemappmonitor.h
        cutefish/dock/systemappmonitor.cpp
        cutefish/dock/systemappitem.h

        cutefish/dock/xwindowinterface.h
        cutefish/dock/xwindowinterface.cpp

        cutefish/dock/docksettings.h
        cutefish/dock/docksettings.cpp

        cutefish/dock/utils.h
        cutefish/dock/utils.cpp

        cutefish/dock/processprovider.h
        cutefish/dock/processprovider.cpp

        MWindowBlur.hpp
        MWindowBlur.cpp

        cutefish/launcher/launchermodel.h
        cutefish/launcher/launchermodel.cpp

        cutefish/launcher/appitem.h
        cutefish/launcher/appitem.cpp

        cutefish/launcher/desktopproperties.h
        cutefish/launcher/desktopproperties.cpp

        cutefish/launcher/processproviderlauncher.h
        cutefish/launcher/processproviderlauncher.cpp

        cutefish/launcher/pagemodel.h
        cutefish/launcher/pagemodel.cpp

        cutefish/launcher/iconitem.cpp
        cutefish/launcher/iconitem.h

        cutefish/statusbar/MMenuPopupWindow.h
        cutefish/statusbar/MMenuPopupWindow.cpp

        cutefish/fishui/MWindowShadow.h
        cutefish/fishui/MWindowShadow.cpp

        cutefish/fishui/tileset.h
        cutefish/fishui/tileset.cpp

        cutefish/fishui/boxshadowrenderer.h
        cutefish/fishui/boxshadowrenderer.cpp

        cutefish/statusbar/MActivity.hpp
        cutefish/statusbar/MActivity.cpp

        cutefish/statusbar/capplications.h
        cutefish/statusbar/capplications.cpp

        cutefish/fishui/iconthemeprovider.cpp
        cutefish/fishui/iconthemeprovider.hpp

        cutefish/statusbar/MBackgroundHelper.h
        cutefish/statusbar/MBackgroundHelper.cpp

        server/LocaleSettingsService.hpp
        server/LocaleSettingsService.cpp
)

# This ensures that cmake_config.h, which is generated in the build
# directory, will be seen by the compiler.
target_include_directories(
    ${PROJECT_NAME}
    PUBLIC
        ${CMAKE_CURRENT_BINARY_DIR}
)

qt6_add_statecharts(
    ${PROJECT_NAME}
    scxml/GuiManagerStateMachine.scxml
)

add_library(MaiaBackendLib STATIC "")

# Make it possible for the main application to use headers,
# e.g. #include <Backend.hpp>.
target_include_directories(
    ${PROJECT_NAME}
    PUBLIC
        ${CMAKE_CURRENT_BINARY_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/dock
        ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/launcher
        ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/statusbar
        ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/fishui
)

target_link_libraries(
    ${PROJECT_NAME}
    PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
        Qt6::Quick
        Qt6::Concurrent

    PUBLIC
        Qt6::Scxml
        Qt6::WebEngineQuick

    PRIVATE
        KF6::ConfigCore
        KF6::WindowSystem

    PUBLIC
        KF6::PulseAudioQt

    # PkgConfig::LIBPULSE
    # PkgConfig::LIBPULSE_MAINLOOP
)

target_link_libraries(
    MaiaBackendLib
    PRIVATE
        MaiaBackend
)

include(GNUInstallDirs)

install(
    TARGETS ${PROJECT_NAME}
    # Executable files (runtime) go to the /bin subdirectory.
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}

    # Libraries (.so, .dll) go to the /lib subdirectory.
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}

    # Files for the archiver/linker go to the /lib subdirectory.
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

# install(TARGETS ${PROJECT_NAME} ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
# install(DIRECTORY assets/wallpapers/
#         DESTINATION ${KDE_INSTALL_WALLPAPERDIR}/Cask)
