cmake_minimum_required(VERSION 3.16)

project(LumenFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

# The frontend is loaded from disk (shell/Main.qml) by the Maia backend, the module is built
# for tooling (qmllint, qmlcachegen checks) and the files are installed as they are.

set(LUMEN_QML_SINGLETONS
    theme/Theme.qml
    shell/state/Shell.qml
)

set_source_files_properties(${LUMEN_QML_SINGLETONS}
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(LumenFrontend
    URI LumenFrontend
    VERSION ${MAIA_VERSION}

    QML_FILES
        shell/Main.qml
        ${LUMEN_QML_SINGLETONS}
        apps/files/CommandBar.qml
        apps/files/DetailsPane.qml
        apps/files/ExplorerButton.qml
        apps/files/ExplorerTab.qml
        apps/files/ExplorerToolTip.qml
        apps/files/FileExplorerWindow.qml
        apps/files/FileView.qml
        apps/files/MockFileSystem.js
        apps/files/NavigationBar.qml
        apps/files/Sidebar.qml
        apps/files/StatusBar.qml
        apps/files/TabStrip.qml
        components/AccentButton.qml
        components/AppTile.qml
        components/CalendarView.qml
        components/Card.qml
        components/FlyoutWindow.qml
        components/JobCard.qml
        components/LIcon.qml
        components/LMenu.qml
        components/LMenuItem.qml
        components/LMenuSeparator.qml
        components/LSlider.qml
        components/LSwitch.qml
        components/LText.qml
        components/LToolTip.qml
        components/NotificationCard.qml
        components/NotificationFiles.qml
        components/ActionGlyphs.js
        components/PasswordField.qml
        components/ProgressRing.qml
        components/SearchBox.qml
        components/StartGlyph.qml
        components/SubtleButton.qml
        components/TaskbarButton.qml
        components/ToggleTile.qml
        shell/desktop/DesktopClock.qml
        shell/desktop/Wallpaper.qml
        shell/services/AppColorSync.qml
        shell/services/CountdownTimer.qml
        shell/services/TimerSound.qml
        shell/windows/CalendarWindow.qml
        shell/windows/DesktopMenuWindow.qml
        shell/windows/TrayIconButton.qml
        shell/windows/TrayPopupWindow.qml
        shell/windows/QuickSettingsWindow.qml
        shell/windows/QuickSettingsWifiPage.qml
        shell/windows/StartMenuWindow.qml
        shell/windows/TaskbarWindow.qml
        shell/windows/TimerWindow.qml
        shell/windows/WidgetsWindow.qml
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Lumen"
    PATTERN "CMakeLists.txt" EXCLUDE
    PATTERN "tests" EXCLUDE
    REGEX "/assets/decorations(/|$)" EXCLUDE
)

# Lumen's window decoration (Se7enAero, an Aurorae SVG theme by Infinality, GPL-2.0) where the
# compositor finds it: <prefix>/share is in XDG_DATA_DIRS of a Maia session. FrontendLook in
# shell/Main.qml makes it Lumen's default (Maia.Appearance).
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/assets/decorations/Se7enAero
    DESTINATION ${KDE_INSTALL_DATADIR}/aurorae/themes
)

# Lumen's components on their own (tests/tst_*.qml), offscreen, from the sources: the module is
# found through a link named after it, the services' modules in the build tree (never a running
# service: their sockets point nowhere)
if(BUILD_TESTING)
    include(MaiaQmlModule)
    find_program(MAIA_QMLTESTRUNNER qmltestrunner HINTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_BINS}")
    if(MAIA_QMLTESTRUNNER)
        set(lumen_test_imports "${CMAKE_CURRENT_BINARY_DIR}/test-imports")
        file(MAKE_DIRECTORY "${lumen_test_imports}")
        file(CREATE_LINK "${CMAKE_CURRENT_SOURCE_DIR}" "${lumen_test_imports}/LumenFrontend" SYMBOLIC)
        add_test(NAME lumen-components
            COMMAND "${MAIA_QMLTESTRUNNER}" -import "${lumen_test_imports}" -import "${MAIA_QML_BUILD_DIR}"
                    -input "${CMAKE_CURRENT_SOURCE_DIR}/tests")
        set_tests_properties(lumen-components PROPERTIES ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;MAIA_POWER_SOCKET=/nonexistent/power.sock;MAIA_NETWORK_SOCKET=/nonexistent/network.sock")
    endif()
endif()
