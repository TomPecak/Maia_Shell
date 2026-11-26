# QML module Maia.Tray: Tray (requests, counts), TrayItemsModel (the items, filtered and in order)
# and TrayMenu (an item's menu while it is open), over the TrayHost of the tray service. For shells.
#
# No user interface: each shell draws the tray in its own style (Maia: a plate by the clock, Lumen:
# the taskbar). An installed QML module (cmake/MaiaQmlModule.cmake); Cap'n Proto (3rdparty/capnproto,
# static) runs in the connection's own thread.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)
find_package(KF6 ${REQUIRED_KF_VERSION} REQUIRED COMPONENTS WindowSystem)

qt_add_library(MaiaTray SHARED)
add_library(Maia::Tray ALIAS MaiaTray)

qt_add_qml_module(MaiaTray
    URI Maia.Tray
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Tray
    SOURCES
        ServiceLink.h ServiceLink.cpp
        TrayData.h
        TrayConnection.h TrayConnection.cpp
        Tray.h Tray.cpp
        TrayItemsModel.h TrayItemsModel.cpp
        TrayMenu.h TrayMenu.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaTray
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/tray.capnp
)
target_include_directories(MaiaTray PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaTray PUBLIC Qt6::Core Qt6::Gui Qt6::Qml PRIVATE KF6::WindowSystem)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaTray PRIVATE)

maia_install_qml_module(MaiaTray URI Maia.Tray)

if(BUILD_TESTING)
    # The module against the real service on a private D-Bus, with tools/fake-tray-item.py as the
    # application
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_tray tests/tst_tray.cpp)
    target_link_libraries(tst_tray PRIVATE Maia::Tray Qt6::Test)
    get_target_property(tray_service maia-tray-service MAIA_CARGO_BINARY)
    target_compile_definitions(tst_tray PRIVATE
        MAIA_TRAY_SERVICE="${tray_service}"
        MAIA_FAKE_TRAY_ITEM="${CMAKE_CURRENT_SOURCE_DIR}/../tools/fake-tray-item.py")
    add_dependencies(tst_tray maia-tray-service)
    add_test(NAME maia-tray-qml COMMAND tst_tray)
    set_tests_properties(maia-tray-qml PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
