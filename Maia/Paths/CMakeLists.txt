# Maia::Paths: where a Maia version keeps its files (MaiaPaths.hpp): ~/.config/maia/<version>/.
# Used by the shell (appMaiaServer) and the apps (maia-settings).

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core)

add_library(MaiaPaths STATIC MaiaPaths.hpp MaiaPaths.cpp)
add_library(Maia::Paths ALIAS MaiaPaths)
set_target_properties(MaiaPaths PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(MaiaPaths PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(MaiaPaths PRIVATE MAIA_VERSION_STRING="${MAIA_VERSION}")
target_link_libraries(MaiaPaths PUBLIC Qt6::Core)
