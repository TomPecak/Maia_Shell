cmake_minimum_required(VERSION 3.16)

project(LumenFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

# The frontend is loaded from disk (Main.qml) by the Maia backend, the module is built
# for tooling (qmllint, qmlcachegen checks) and the files are installed as they are.

set(LUMEN_QML_SINGLETONS
    theme/Theme.qml
    shell/Shell.qml
)

set_source_files_properties(${LUMEN_QML_SINGLETONS}
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(LumenFrontend
    URI LumenFrontend
    VERSION ${MAIA_VERSION}

    QML_FILES
        Main.qml
        ${LUMEN_QML_SINGLETONS}
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
        components/SearchBox.qml
        components/StartGlyph.qml
        components/SubtleButton.qml
        components/TaskbarButton.qml
        components/ToggleTile.qml
        desktop/DesktopClock.qml
        desktop/Wallpaper.qml
        services/AppColorSync.qml
        windows/CalendarWindow.qml
        windows/DesktopMenuWindow.qml
        windows/QuickSettingsWindow.qml
        windows/StartMenuWindow.qml
        windows/TaskbarWindow.qml
        windows/WidgetsWindow.qml
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Lumen"
    PATTERN "CMakeLists.txt" EXCLUDE
)
