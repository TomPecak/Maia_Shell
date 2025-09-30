cmake_minimum_required(VERSION 3.16)

project(GnomeFrontend VERSION 1.0 LANGUAGES CXX)

set(REQUIRED_QT_VERSION 6.8)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_library(GnomeFrontend STATIC)

set(GNOME_QML_FILES
        Main.qml

        SidePanelContent.qml

        common_qml/ActionButton.qml

        contents/AppLauncherContent.qml
        contents/ControlBoardContent.qml
        contents/TopPanelContent.qml

        popups/ControlBoardPopup.qml

        style/UIStyle.qml
        style/GMenu.qml
        style/GMenuItem.qml
        style/GMenuSeparator.qml
        style/GTextField.qml

        windows/AppsLauncherWindow.qml
        windows/ControlBoardWindow.qml
)

qt_add_qml_module(GnomeFrontend
        URI GnomeFrontend
        VERSION 1.0

        QML_FILES
        ${GNOME_QML_FILES}
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Gnome"
)





