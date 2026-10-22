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
        components/LIcon.qml
        components/LMenu.qml
        components/LMenuItem.qml
        components/LMenuSeparator.qml
        components/LSlider.qml
        components/LSwitch.qml
        components/LText.qml
        components/NotificationCard.qml
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
        shell/windows/QuickSettingsWindow.qml
        shell/windows/StartMenuWindow.qml
        shell/windows/TaskbarWindow.qml
        shell/windows/TimerWindow.qml
        shell/windows/WidgetsWindow.qml
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Lumen"
    PATTERN "CMakeLists.txt" EXCLUDE
)
