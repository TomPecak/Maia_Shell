# QML module Maia.Network: the state of Wi-Fi and its control, on top of the network service.
#
# Models and objects, no user interface: shells (quick settings, status icons), Maia Settings and
# app faces draw them in their own style. An installed QML module (cmake/MaiaQmlModule.cmake): the
# shared library libMaiaNetwork with the types, and its plugin in <prefix>/<qml dir>/Maia/Network.
# Cap'n Proto (3rdparty/capnproto, static) is used only inside NetworkConnection.cpp.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)

qt_add_library(MaiaNetwork SHARED)

qt_add_qml_module(MaiaNetwork
    URI Maia.Network
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Network
    SOURCES
        NetworkTypes.h
        NetworkSource.h NetworkSource.cpp
        NetworkConnection.h NetworkConnection.cpp
        QmlHelpers.h
        WifiStatus.h WifiStatus.cpp
        WifiNetworksModel.h WifiNetworksModel.cpp
        SavedNetworksModel.h SavedNetworksModel.cpp
        WifiDevicesModel.h WifiDevicesModel.cpp
        SecretPrompt.h SecretPrompt.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaNetwork
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/network.capnp
)
target_include_directories(MaiaNetwork PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaNetwork PUBLIC Qt6::Core Qt6::Gui Qt6::Qml)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaNetwork PRIVATE)

maia_install_qml_module(MaiaNetwork URI Maia.Network)

if(BUILD_TESTING)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_networkmodels tests/tst_networkmodels.cpp)
    target_link_libraries(tst_networkmodels PRIVATE MaiaNetwork Qt6::Test)
    add_test(NAME maia-network-models COMMAND tst_networkmodels)
    set_tests_properties(maia-network-models PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
