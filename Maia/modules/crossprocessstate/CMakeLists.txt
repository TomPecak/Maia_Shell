# QML module Maia.CrossProcessState: properties and signals shared by the processes of a session
# (the layers of a shell are separate processes), declared in QML like Settings {}. One process
# hosts the state (host: true), the others take part; a Unix socket between them, never blocking,
# never polling. No service behind it: the library is the whole of it. See CrossProcessState.h and
# Link.h.

include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Network Qml)

qt_add_library(MaiaCrossProcessState SHARED)
add_library(Maia::CrossProcessState ALIAS MaiaCrossProcessState)

qt_add_qml_module(MaiaCrossProcessState
    URI Maia.CrossProcessState
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/CrossProcessState
    SOURCES
        Protocol.h Protocol.cpp
        Link.h Link.cpp
        CrossProcessState.h CrossProcessState.cpp
)

target_include_directories(MaiaCrossProcessState PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaCrossProcessState PUBLIC Qt6::Core Qt6::Qml PRIVATE Qt6::Network)

maia_install_qml_module(MaiaCrossProcessState URI Maia.CrossProcessState)

if(BUILD_TESTING)
    # Real processes: a peer program (tests/peer.cpp) loads a CrossProcessState in QML and is driven
    # through its standard input; the test starts hosts and participants and reads what they see
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Gui Test)
    add_executable(crossprocessstate-peer tests/peer.cpp)
    target_link_libraries(crossprocessstate-peer PRIVATE Qt6::Gui Qt6::Qml)
    target_compile_definitions(crossprocessstate-peer PRIVATE MAIA_QML_BUILD_DIR="${MAIA_QML_BUILD_DIR}")
    add_dependencies(crossprocessstate-peer MaiaCrossProcessStateplugin)

    add_executable(tst_crossprocessstate tests/tst_crossprocessstate.cpp)
    target_link_libraries(tst_crossprocessstate PRIVATE Maia::CrossProcessState Qt6::Gui Qt6::Network Qt6::Qml Qt6::Test)
    target_compile_definitions(tst_crossprocessstate PRIVATE
        PEER_PROGRAM="$<TARGET_FILE:crossprocessstate-peer>" MAIA_QML_BUILD_DIR="${MAIA_QML_BUILD_DIR}")
    add_dependencies(tst_crossprocessstate crossprocessstate-peer)
    add_test(NAME maia-crossprocessstate COMMAND tst_crossprocessstate)
    set_tests_properties(maia-crossprocessstate PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
