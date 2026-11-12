# QML module Maia.Power: the batteries, the brightness of the screen and the keyboard, the power
# profile, on top of the power service.
#
# No user interface: shells (the battery icon, quick settings), Maia Settings and app faces draw it
# in their own style. An installed QML module (cmake/MaiaQmlModule.cmake): the shared library
# libMaiaPower with the types, and its plugin in <prefix>/<qml dir>/Maia/Power. Cap'n Proto
# (3rdparty/capnproto, static) is used only inside PowerConnection.cpp.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)

qt_add_library(MaiaPower SHARED)
add_library(Maia::Power ALIAS MaiaPower)

qt_add_qml_module(MaiaPower
    URI Maia.Power
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Power
    SOURCES
        PowerConnection.h PowerConnection.cpp
        Power.h Power.cpp
        BatteriesModel.h BatteriesModel.cpp
        DisplaysModel.h DisplaysModel.cpp
        ProfileHold.h ProfileHold.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaPower
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/power.capnp
)
target_include_directories(MaiaPower PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaPower PUBLIC Qt6::Core Qt6::Gui Qt6::Qml)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaPower PRIVATE)

maia_install_qml_module(MaiaPower URI Maia.Power)

if(BUILD_TESTING)
    # The module against the real service with its fake backend (a simulated laptop)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_power tests/tst_power.cpp)
    target_link_libraries(tst_power PRIVATE Maia::Power Qt6::Test)
    get_target_property(power_service maia-power-service MAIA_CARGO_BINARY)
    target_compile_definitions(tst_power PRIVATE MAIA_POWER_SERVICE="${power_service}")
    add_dependencies(tst_power maia-power-service)
    add_test(NAME maia-power-qml COMMAND tst_power)
    set_tests_properties(maia-power-qml PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
