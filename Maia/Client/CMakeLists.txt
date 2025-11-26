cmake_minimum_required(VERSION 3.16)
project(MaiaClient VERSION ${MAIA_VERSION} LANGUAGES CXX)

set(PROJECT_URI Maia.Client)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED NO_MODULE COMPONENTS Core Quick DBus)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})
qt_add_library(${PROJECT_NAME} STATIC)

qt_add_qml_module(${PROJECT_NAME}
    URI ${PROJECT_URI}
    VERSION 1.0
    SOURCES MLocaleSettings.hpp
    SOURCES MLocaleSettings.cpp
)

target_include_directories(${PROJECT_NAME} PUBLIC
    # ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)


target_link_libraries(${PROJECT_NAME}
    PRIVATE Qt6::Core
    PRIVATE Qt6::DBus
    PRIVATE Qt6::Quick
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
