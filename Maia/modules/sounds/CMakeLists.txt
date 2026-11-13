# QML module Maia.Sounds: short event sounds (a notification, a change of the volume, an error) for
# shells and apps. A name of the freedesktop sound theme or a file goes in, the player plays it in
# its own thread through libcanberra (loaded at run time). No look, and no service behind it yet: a
# future audio service may take the requests over without anything changing for the users.

include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Qml)

qt_add_library(MaiaSounds SHARED)
add_library(Maia::Sounds ALIAS MaiaSounds)

qt_add_qml_module(MaiaSounds
    URI Maia.Sounds
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Sounds
    SOURCES
        SoundPlayer.h
        CanberraPlayer.h CanberraPlayer.cpp
        Sounds.h Sounds.cpp
)

target_include_directories(MaiaSounds PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaSounds PUBLIC Qt6::Core Qt6::Qml PRIVATE ${CMAKE_DL_LIBS})

maia_install_qml_module(MaiaSounds URI Maia.Sounds)

if(BUILD_TESTING)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_sounds tests/tst_sounds.cpp)
    target_link_libraries(tst_sounds PRIVATE Maia::Sounds Qt6::Test)
    add_test(NAME maia-sounds COMMAND tst_sounds)
    set_tests_properties(maia-sounds PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
