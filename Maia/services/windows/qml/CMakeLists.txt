# QML module Maia.Windows: TasksModel (the API of org.kde.taskmanager) on top of the window service.
#
# An installed QML module, loaded at run time by every process that imports it (the shell, apps):
# the shared library libMaiaWindows with the types, and its QML plugin in
# <prefix>/<qml dir>/Maia/Windows (cmake/MaiaQmlModule.cmake). Only the QML API is public.
# Cap'n Proto (3rdparty/capnproto, static) is used only inside ServiceConnection.cpp.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)

qt_add_library(MaiaWindows SHARED)
add_library(Maia::Windows ALIAS MaiaWindows)

qt_add_qml_module(MaiaWindows
    URI Maia.Windows
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Windows
    SOURCES
        WindowInfo.h
        WindowSource.h WindowSource.cpp
        ServiceConnection.h ServiceConnection.cpp
        AbstractTasksModel.h
        TasksModel.h TasksModel.cpp
)

# C++ code of the contract (shared with the Rust service); also links Maia::CapnProto
maia_capnp_generate_cpp(MaiaWindows
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/windows.capnp
)
target_include_directories(MaiaWindows PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaWindows PUBLIC Qt6::Core Qt6::Gui Qt6::Qml)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaWindows PRIVATE)

maia_install_qml_module(MaiaWindows URI Maia.Windows)

if(BUILD_TESTING)
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_tasksmodel tests/tst_tasksmodel.cpp)
    target_link_libraries(tst_tasksmodel PRIVATE Maia::Windows Qt6::Test)
    add_test(NAME maia-windows-tasksmodel COMMAND tst_tasksmodel)
    set_tests_properties(maia-windows-tasksmodel PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
