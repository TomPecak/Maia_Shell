cmake_minimum_required(VERSION 3.16)

project(XPLunaFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(REQUIRED_QT_VERSION 6.8)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_library(XPLunaFrontend STATIC)

set(XPLUNA_QML_FILES
    Main.qml
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
