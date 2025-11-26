cmake_minimum_required(VERSION 3.16)

project(MaiaServerApp VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(ECMGenerateHeaders)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Quick Quick3D DBus WebEngineQuick WebSockets)

# Generate maia_version.h file with version #definitions, file will be generated in build directories
ecm_setup_version(${MAIA_VERSION}
    VARIABLE_PREFIX MAIA
    VERSION_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/maia_version.h"
    PACKAGE_VERSION_FILE "${CMAKE_CURRENT_BINARY_DIR}/MaiaConfigVersion.cmake"
    SOVERSION ${PROJECT_VERSION_MAJOR})

set(DEPLOY_FILES
    "maia_0.1.0-desktop.desktop"
)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_executable(appMaiaServer
    main.cpp
    main_proxy_window.cpp
    main_server.cpp
    main_server.hpp
    main_proxy_window.hpp
    logger.hpp
    logger.cpp
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appMaiaServer PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appMaiaServer
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appMaiaServer
    PRIVATE Qt6::Core
    PRIVATE Qt6::Quick
    PRIVATE Qt6::DBus
    PRIVATE Qt6::Quick3D
    PUBLIC Qt6::WebEngineQuick
    PRIVATE Qt6::WebSockets
)

# FIX: Prevent linker from stripping QML registration code from the static MaiaClient lib.
# Since auto-generated QML types aren't explicitly referenced in C++, the linker
# discards them as "unused", causing "MLocaleSettings is not a type" errors.
# --whole-archive forces inclusion of all symbols; --no-whole-archive resets behavior.
target_link_libraries(appMaiaServer
    PUBLIC
    -Wl,--whole-archive MaiaClient -Wl,--no-whole-archive
)
target_link_libraries(appMaiaServer PRIVATE MaiaBackend)


include(GNUInstallDirs)

install(TARGETS appMaiaServer
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Generowanie skryptu do deployowania aplikacji Qt Quick
qt_generate_deploy_qml_app_script(
    TARGET appMaiaServer
    OUTPUT_SCRIPT deploy_script
)

# Instalacja skryptu (gdzie skrypt będzie uruchomiony podczas instalacji)
install(SCRIPT ${deploy_script})

# Deploy maia_version-desktop.desktop file
install(FILES ${DEPLOY_FILES}
        DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
        PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
)

