cmake_minimum_required(VERSION 3.16)

project(Logger VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 WebSockets)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appLogger
    main.cpp
)

qt_add_qml_module(appLogger
    URI Logger
    VERSION 1.0
    QML_FILES
        Main.qml
        SOURCES LoggerBackend.hpp
        SOURCES LoggerBackend.cpp
        SOURCES Server.hpp
        SOURCES Server.cpp
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appLogger PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appLogger
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appLogger
    PRIVATE Qt6::Quick
    PRIVATE Qt6::QuickControls2
    PRIVATE Qt6::WebSockets
)

include(GNUInstallDirs)
install(TARGETS appLogger
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
