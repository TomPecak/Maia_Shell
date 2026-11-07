# Maia Settings (maia-settings): the system settings of Maia.
#
# Not a monolith: the program is a frame (navigation, search, sub-pages, dialogs, messages) and
# the pages are found at run time. Each page is a directory with metadata.json and its QML files
# (pages/<id>/, installed to <datadir>/maia-settings/pages/<id>/), built on the QML modules of the
# services (Maia.Network, ...) and on the components of the frame (Maia.SettingsKit). A page can
# also come from another package. See README.md.
#
# The desktop face uses the Lumen frontend's theme and components (import LumenFrontend).

cmake_minimum_required(VERSION 3.21)
project(MaiaSettings VERSION ${MAIA_VERSION} LANGUAGES CXX)

include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_executable(maia-settings src/main.cpp)

set_source_files_properties(qml/SettingsApp.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(maia-settings
    URI Maia.SettingsKit
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/SettingsApp.qml
        qml/SettingsPage.qml
        qml/NavigationPane.qml
        qml/PageHeader.qml
        qml/SettingsGroup.qml
        qml/SettingsCard.qml
        qml/StandardButton.qml
        qml/ComboField.qml
        qml/FormField.qml
        qml/ContentDialog.qml
        qml/InfoBar.qml
        qml/Toast.qml
        qml/SelectorBar.qml
        qml/EmptyState.qml
        qml/IconButton.qml
        qml/ToolTipArea.qml
    SOURCES
        src/SettingsPages.h src/SettingsPages.cpp
        src/SingleInstance.h src/SingleInstance.cpp
)

target_include_directories(maia-settings PRIVATE src)
# Maia::FrontendModules: the frontend module symlink, the same rule as the shell
target_link_libraries(maia-settings PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Network
    Maia::FrontendModules)
maia_target_qml_import_dir(maia-settings)
target_compile_definitions(maia-settings PRIVATE
    MAIA_VERSION_STRING="${MAIA_VERSION}"
    MAIA_SETTINGS_PAGES_DIR="${KDE_INSTALL_FULL_DATADIR}/maia-settings/pages"
    MAIA_SETTINGS_BUILD_PAGES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/pages"
    MAIA_FRONTENDS_DIR="${CMAKE_INSTALL_PREFIX}/frontends"
)
# The pages import these at run time
maia_target_qml_imports(maia-settings Maia.Network)

install(TARGETS maia-settings ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
install(FILES org.maia.settings.desktop DESTINATION ${KDE_INSTALL_APPDIR})

add_subdirectory(pages/network)
