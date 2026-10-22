cmake_minimum_required(VERSION 3.16)

project(CutefishFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)


find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

set(CUTEFISH_QML_FILES
    shell/Main.qml
)

set(CUTEFISH_QML_SINGLETONS
        FishUI/Units.qml
        FishUI/Theme.qml
)

set_source_files_properties(${CUTEFISH_QML_SINGLETONS}
        PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(CutefishFrontend
        URI CutefishFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES
        ${CUTEFISH_QML_FILES}
        QML_FILES shell/menu/ChangeFrontendMenu.qml
        QML_FILES shell/contents/WallpaperContent.qml
        QML_FILES shell/contents/DockContent.qml
        QML_FILES shell/items/AppItem.qml
        QML_FILES shell/items/DockItem.qml
        QML_FILES shell/windows/DockWindow.qml
        QML_FILES shell/popups/PopupTips.qml
        ${CUTEFISH_QML_SINGLETONS}
        QML_FILES shell/launcher/AppsLauncherWindow.qml
        QML_FILES shell/launcher/LauncherContent.qml
        QML_FILES shell/launcher/AllAppsView.qml
        QML_FILES shell/launcher/GridItemDelegate.qml
        QML_FILES shell/statusbar/StatusbarWindow.qml
        QML_FILES shell/statusbar/StatusbarContent.qml
        QML_FILES shell/statusbar/StandardItem.qml
        QML_FILES shell/menu/DesktopMenu.qml
        QML_FILES shell/control_center/ControlCenter.qml
)


install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Cutefish"
)
