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

# Generate maia_version.h file with version #definitions, file will be generated in build directories
ecm_setup_version(${MAIA_VERSION}
    VARIABLE_PREFIX MAIA
    VERSION_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/maia_version.h"
    PACKAGE_VERSION_FILE "${CMAKE_CURRENT_BINARY_DIR}/MaiaConfigVersion.cmake"
    SOVERSION ${PROJECT_VERSION_MAJOR})


find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED NO_MODULE COMPONENTS Core Gui Quick DBus Concurrent Scxml WebEngineQuick)
find_package(KF6 ${REQUIRED_KF_VERSION} REQUIRED COMPONENTS Config WindowSystem)

find_package(KF6PulseAudioQt ${REQUIRED_PULSEAUDIOQT_VERSION} REQUIRED)

pkg_check_modules(XCB_SHAPE REQUIRED IMPORTED_TARGET xcb-shape)
pkg_check_modules(XCB_ICCCM REQUIRED IMPORTED_TARGET xcb-icccm)

qt_add_library(${PROJECT_NAME} STATIC)

# Generate cmake_config.h with CMAKE_INSTALL_PREFIX
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

    SOURCES BackendAppsIconsProvider.hpp
    SOURCES TaskbarIconProvider.hpp
    SOURCES TaskbarIconProvider.cpp
    SOURCES MAudioBackend.hpp
    SOURCES MAudioBackend.cpp
    SOURCES ThemesModel.hpp
    SOURCES ThemesModel.cpp
    SOURCES helper/Process.hpp
    SOURCES helper/Process.cpp
    SOURCES private/Mask.hpp
    SOURCES private/Mask.cpp
    SOURCES MMaskedItem.hpp
    SOURCES MMaskedItem.cpp
    SOURCES MKdeColorScheme.hpp
    SOURCES MKdeColorScheme.cpp
    SOURCES MaskArea.hpp
    SOURCES MaskArea.cpp
    SOURCES private/MaskTracker.hpp
    SOURCES private/MaskTracker.cpp
    SOURCES private/MaskAlgorithm.hpp
    SOURCES private/MaskAlgorithm.cpp
    SOURCES private/WindowInputMask.hpp
    SOURCES private/WindowInputMask.cpp
    SOURCES strut/Strut.hpp
    SOURCES strut/StrutManager.hpp
    SOURCES strut/StrutManager.cpp
    SOURCES MSessionManager.hpp
    SOURCES MSessionManager.cpp
    SOURCES server/SessionService.hpp
    SOURCES server/SessionService.cpp
    SOURCES server/Server.hpp
    SOURCES server/Server.cpp
    SOURCES MTaskbarModel.hpp
    SOURCES MTaskbarModel.cpp
    SOURCES MTaskbarBaseModel.hpp
    SOURCES MTaskbarBaseModel.cpp
    SOURCES MFrontendModel.hpp
    SOURCES MFrontendModel.cpp
    SOURCES server/FrontendManagerService.hpp
    SOURCES server/FrontendManagerService.cpp
    SOURCES private/ProxyWindowServer.cpp
    SOURCES private/ProxyWindowServer.hpp
    SOURCES server/X11WindowManagerService.hpp
    SOURCES server/X11WindowManagerService.cpp
    SOURCES MWindowManagerX11.hpp
    SOURCES MWindowManagerX11.cpp
    SOURCES server/QmlGui.hpp
    SOURCES server/QmlGui.cpp
    SOURCES server/FrontendModules.hpp
    SOURCES server/FrontendModules.cpp
    SOURCES server/FrontendLoader.hpp
    SOURCES server/FrontendLoader.cpp
    SOURCES client/private/ProxyWindowController.hpp
    SOURCES client/private/ProxyWindowController.cpp
    SOURCES MProxyWindow.hpp
    SOURCES MProxyWindow.cpp
    SOURCES server/FavoriteAppsService.hpp
    SOURCES server/FavoriteAppsService.cpp
    SOURCES server/Application.hpp
    SOURCES server/Application.cpp
    SOURCES MFavoritesAppsModel.hpp
    SOURCES MFavoritesAppsModel.cpp
    SOURCES server/FavoriteAppsListModel.hpp
    SOURCES audio/MPreferredDevice.hpp
    SOURCES audio/MPreferredDevice.cpp
    SOURCES server/FrontendInfo.hpp
    SOURCES cmake_config.h.in
    SOURCES MIconItem.hpp
    SOURCES MIconItem.cpp
    SOURCES cutefish/dock/applicationmodel.h
    SOURCES cutefish/dock/applicationmodel.cpp
    SOURCES cutefish/dock/applicationitem.h
    SOURCES cutefish/dock/systemappmonitor.h
    SOURCES cutefish/dock/systemappmonitor.cpp
    SOURCES cutefish/dock/systemappitem.h
    SOURCES cutefish/dock/systemappitem.cpp
    SOURCES cutefish/dock/xwindowinterface.h
    SOURCES cutefish/dock/xwindowinterface.cpp
    SOURCES cutefish/dock/docksettings.h
    SOURCES cutefish/dock/docksettings.cpp
    SOURCES cutefish/dock/utils.h
    SOURCES cutefish/dock/utils.cpp
    SOURCES cutefish/dock/processprovider.h
    SOURCES cutefish/dock/processprovider.cpp
    SOURCES MWindowBlur.hpp
    SOURCES MWindowBlur.cpp
    SOURCES cutefish/launcher/launchermodel.h
    SOURCES cutefish/launcher/launchermodel.cpp
    SOURCES cutefish/launcher/appitem.h
    SOURCES cutefish/launcher/appitem.cpp
    SOURCES cutefish/launcher/desktopproperties.h
    SOURCES cutefish/launcher/desktopproperties.cpp
    SOURCES cutefish/launcher/processproviderlauncher.h
    SOURCES cutefish/launcher/processproviderlauncher.cpp
    SOURCES cutefish/launcher/pagemodel.h
    SOURCES cutefish/launcher/pagemodel.cpp
    SOURCES cutefish/launcher/iconitem.cpp
    SOURCES cutefish/launcher/iconitem.h
    SOURCES cutefish/statusbar/MMenuPopupWindow.h
    SOURCES cutefish/statusbar/MMenuPopupWindow.cpp
    SOURCES cutefish/fishui/MWindowShadow.h
    SOURCES cutefish/fishui/MWindowShadow.cpp
    SOURCES cutefish/fishui/tileset.h
    SOURCES cutefish/fishui/tileset.cpp
    SOURCES cutefish/fishui/boxshadowrenderer.h
    SOURCES cutefish/fishui/boxshadowrenderer.cpp
    SOURCES cutefish/statusbar/MActivity.hpp
    SOURCES cutefish/statusbar/MActivity.cpp
    SOURCES cutefish/statusbar/capplications.h
    SOURCES cutefish/statusbar/capplications.cpp
    SOURCES cutefish/fishui/iconthemeprovider.cpp
    SOURCES cutefish/fishui/iconthemeprovider.hpp
    SOURCES cutefish/statusbar/MBackgroundHelper.h
    SOURCES cutefish/statusbar/MBackgroundHelper.cpp
    SOURCES
    SOURCES
    SOURCES server/LocaleSettingsService.hpp
    SOURCES server/LocaleSettingsService.cpp
)

# This ensures that cmake_config.h, which is generated in the build directory, will be seen by the compiler
target_include_directories(${PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_BINARY_DIR})

qt6_add_statecharts(${PROJECT_NAME}
    scxml/GuiManagerStateMachine.scxml
)

# D-Bus contract of the frontend manager: the adaptor for the service (FrontendManagerAdaptor) and the
# proxy for the clients (FrontendManagerInterface) are both generated from the same XML
set(FRONTEND_MANAGER_DBUS_XML ${CMAKE_CURRENT_SOURCE_DIR}/dbus/org.maia.FrontendManager.xml)
set_source_files_properties(${FRONTEND_MANAGER_DBUS_XML} PROPERTIES CLASSNAME FrontendManagerInterface)
qt_add_dbus_adaptor(FRONTEND_MANAGER_DBUS_SOURCES ${FRONTEND_MANAGER_DBUS_XML}
    ${CMAKE_CURRENT_SOURCE_DIR}/server/FrontendManagerService.hpp FrontendManagerService
    frontendmanager_adaptor FrontendManagerAdaptor)
qt_add_dbus_interface(FRONTEND_MANAGER_DBUS_SOURCES ${FRONTEND_MANAGER_DBUS_XML} frontendmanager_interface)
target_sources(${PROJECT_NAME} PRIVATE ${FRONTEND_MANAGER_DBUS_SOURCES})




#so that in the main application it would be possible to use headers, e.g., #include <Backend.hpp>
target_include_directories(${PROJECT_NAME} PUBLIC
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/dock
    ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/launcher
    ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/statusbar
    ${CMAKE_CURRENT_SOURCE_DIR}/cutefish/fishui
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE Qt6::Core
    PRIVATE Qt6::DBus
    PRIVATE Qt6::Gui
    PRIVATE Qt6::Quick
    PRIVATE Qt6::Concurrent
    PUBLIC Qt6::Scxml
    PUBLIC Qt6::WebEngineQuick
    PRIVATE KF6::ConfigCore
    PRIVATE KF6::WindowSystem
    PRIVATE KF6::PulseAudioQt
    # PkgConfig::LIBPULSE
    # PkgConfig::LIBPULSE_MAINLOOP

    PRIVATE PkgConfig::XCB_SHAPE
    PRIVATE PkgConfig::XCB_ICCCM
)


include(GNUInstallDirs)

install(TARGETS ${PROJECT_NAME}
    # Executable files (runtime) go to the /bin subdirectory
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    # Libraries (.so, .dll) go to the /lib subdirectory
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    # Files for the archiver/linker go to the /lib subdirectory
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

#install(TARGETS ${PROJECT_NAME} ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
#install(DIRECTORY assets/wallpapers/ DESTINATION ${KDE_INSTALL_WALLPAPERDIR}/Cask)
