cmake_minimum_required(VERSION 3.16)

project(MaiaFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_qml_module(MaiaFrontend
        URI MaiaFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES Main.qml
        QML_FILES BottomLayer.qml
)


install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Maia"
)