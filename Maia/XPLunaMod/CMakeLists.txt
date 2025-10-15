cmake_minimum_required(VERSION 3.16)

project(XPLunaFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(REQUIRED_QT_VERSION 6.8)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_library(XPLunaFrontend STATIC)

set(XPLUNA_QML_FILES
    Main.qml
    WallpaperContent.qml
    style_items/XPMenu.qml
    style_items/TiledImage.qml
)

qt_add_qml_module(XPLunaFrontend
        URI XPLunaFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES
        ${XPLUNA_QML_FILES}
        QML_FILES style_items/XPMenuItem.qml
        QML_FILES style_items/XPMenuSeparator.qml
        QML_FILES TurnOffContent.qml
        QML_FILES LogoutContent.qml
        QML_FILES windows/AppMenuWindow.qml
        QML_FILES contents/AppMenuContent.qml
        QML_FILES TaskbarContent.qml
        QML_FILES TaskbarButton.qml
        QML_FILES windows/SystemVolumeWindow.qml
        QML_FILES contents/SystemVolumeContent.qml
        QML_FILES style_items/TiledImageVertical.qml
        QML_FILES components/LicenseWarning.qml
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/XPLuna"
)
