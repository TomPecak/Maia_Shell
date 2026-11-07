# Maia::FrontendModules: makes a frontend's QML module (import LumenFrontend, ...) importable by name in
# a QML engine (FrontendModules.hpp). Used by the shell (appMaiaServer) and by the apps that take the
# look of a frontend (maia-settings).

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Qml)

add_library(MaiaFrontendModules STATIC FrontendModules.hpp FrontendModules.cpp)
add_library(Maia::FrontendModules ALIAS MaiaFrontendModules)
set_target_properties(MaiaFrontendModules PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(MaiaFrontendModules PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaFrontendModules PUBLIC Qt6::Core Qt6::Qml)
