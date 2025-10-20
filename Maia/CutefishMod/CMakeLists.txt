cmake_minimum_required(VERSION 3.16)

project(CutefishFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(REQUIRED_QT_VERSION 6.8)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

set(CUTEFISH_QML_FILES
    Main.qml
)

qt_add_qml_module(CutefishFrontend
        URI CutefishFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES
        ${CUTEFISH_QML_FILES}
        QML_FILES menu/ChangeFrontendMenu.qml
        QML_FILES contents/WallpaperContent.qml
        QML_FILES contents/DockContent.qml
        QML_FILES items/AppItem.qml
        QML_FILES items/DockItem.qml
        QML_FILES windows/DockWindow.qml
        QML_FILES popups/PopupTips.qml
)


install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Cutefish"
)
