# QML module Maia.Session: the session (state, what the system offers, logout, power off, sleep)
# on top of the session service.
#
# No user interface: shells and app faces draw the session menu in their own style. An installed
# QML module (cmake/MaiaQmlModule.cmake): the shared library libMaiaSession with the types, and its
# plugin in <prefix>/<qml dir>/Maia/Session. Cap'n Proto (3rdparty/capnproto, static) is used only
# inside SessionConnection.cpp.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Qml)

qt_add_library(MaiaSession SHARED)
add_library(Maia::Session ALIAS MaiaSession)

qt_add_qml_module(MaiaSession
    URI Maia.Session
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Session
    SOURCES
        SessionConnection.h SessionConnection.cpp
        Session.h Session.cpp
        SessionChildrenModel.h SessionChildrenModel.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaSession
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/session.capnp
)
target_include_directories(MaiaSession PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaSession PUBLIC Qt6::Core Qt6::Qml)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaSession PRIVATE)

maia_install_qml_module(MaiaSession URI Maia.Session)

if(BUILD_TESTING)
    # The module against the real service (with a fake compositor, fake processes and fake logind)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_session tests/tst_session.cpp)
    target_link_libraries(tst_session PRIVATE Maia::Session Qt6::Test)
    get_target_property(session_service maia-session-service MAIA_CARGO_BINARY)
    target_compile_definitions(tst_session PRIVATE MAIA_SESSION_SERVICE="${session_service}")
    add_dependencies(tst_session maia-session-service)
    add_test(NAME maia-session-qml COMMAND tst_session)
    set_tests_properties(maia-session-qml PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
