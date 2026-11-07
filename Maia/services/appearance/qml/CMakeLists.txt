# QML module Maia.Appearance: the look of the session, on top of the appearance service.
#
# Objects and models, no user interface: shells and Maia Settings draw them in their own style.
# An installed QML module (cmake/MaiaQmlModule.cmake): the shared library libMaiaAppearance with
# the types, and its plugin in <prefix>/<qml dir>/Maia/Appearance. Cap'n Proto (3rdparty/capnproto,
# static) is used only inside AppearanceConnection.cpp.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)

qt_add_library(MaiaAppearance SHARED)
add_library(Maia::Appearance ALIAS MaiaAppearance)

qt_add_qml_module(MaiaAppearance
    URI Maia.Appearance
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Appearance
    SOURCES
        AppearanceTypes.h
        AppearanceSource.h AppearanceSource.cpp
        AppearanceConnection.h AppearanceConnection.cpp
        WindowDecorations.h WindowDecorations.cpp
        FrontendLook.h FrontendLook.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaAppearance
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS
        ${CMAKE_CURRENT_SOURCE_DIR}/../contract/common.capnp
        ${CMAKE_CURRENT_SOURCE_DIR}/../contract/decorations.capnp
        ${CMAKE_CURRENT_SOURCE_DIR}/../contract/appearance.capnp
)
target_include_directories(MaiaAppearance PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaAppearance PUBLIC Qt6::Core Qt6::Gui Qt6::Qml)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaAppearance PRIVATE)

maia_install_qml_module(MaiaAppearance URI Maia.Appearance)

if(BUILD_TESTING)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_appearance tests/tst_appearance.cpp)
    target_link_libraries(tst_appearance PRIVATE Maia::Appearance Qt6::Test)
    add_test(NAME maia-appearance-model COMMAND tst_appearance)
    set_tests_properties(maia-appearance-model PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
