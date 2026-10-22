cmake_minimum_required(VERSION 3.16)

project(ExperimentalFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

# The frontend is loaded from disk (shell/Main.qml) by the Maia backend, the module is built
# for tooling (qmllint, qmlcachegen checks) and the files are installed as they are.

qt_add_qml_module(ExperimentalFrontend
    URI ExperimentalFrontend
    VERSION ${MAIA_VERSION}

    QML_FILES
        shell/Main.qml
        shell/ExperimentWindow.qml
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Experimental"
    PATTERN "CMakeLists.txt" EXCLUDE
)
