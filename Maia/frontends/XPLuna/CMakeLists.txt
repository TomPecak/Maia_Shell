cmake_minimum_required(VERSION 3.16)

project(XPLunaFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(REQUIRED_QT_VERSION 6.8)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_library(XPLunaFrontend STATIC)

set(XPLUNA_QML_FILES
    # shared by the shell and the apps (module XPLunaFrontend)
    style_items/TiledImage.qml
    style_items/TiledImageVertical.qml
    style_items/XPMenu.qml
    style_items/XPMenuItem.qml
    style_items/XPMenuSeparator.qml
    components/LicenseWarning.qml

    # shell, one directory per part of the GUI
    shell/Main.qml
    shell/desktop/WallpaperContent.qml
    shell/desktop/StickyNotes.qml
    shell/desktop/BrandingLabel.qml
    shell/taskbar/TaskbarContent.qml
    shell/taskbar/TaskbarButton.qml
    shell/startmenu/AppMenuWindow.qml
    shell/startmenu/AppMenuContent.qml
    shell/volume/SystemVolumeWindow.qml
    shell/volume/SystemVolumeContent.qml
    shell/session/TurnOffDialog.qml
    shell/session/TurnOffContent.qml
    shell/session/LogoutDialog.qml
    shell/session/LogoutContent.qml
)

qt_add_qml_module(XPLunaFrontend
        URI XPLunaFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES
        ${XPLUNA_QML_FILES}
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/XPLuna"
)
