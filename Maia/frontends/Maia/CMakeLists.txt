cmake_minimum_required(VERSION 3.16)

project(MaiaFrontend VERSION ${MAIA_VERSION} LANGUAGES CXX)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Quick)

qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_qml_module(MaiaFrontend
        URI MaiaFrontend
        VERSION ${MAIA_VERSION}

        QML_FILES shell/Main.qml
        QML_FILES shell/LayerBottom.qml
        QML_FILES shell/AvailableFonts.qml
        QML_FILES shell/LayerTop.qml
        QML_FILES shell/dock/Dock.qml
        QML_FILES shell/dock/DockButton.qml
        QML_FILES shell/dock/DockPanel.qml
        QML_FILES shell/dock/DockSeparator.qml
        QML_FILES shell/menu/DesktopMenu.qml
        QML_FILES shell/menu/MenuItem.qml
        QML_FILES shell/menu/MenuPanel.qml
        QML_FILES shell/menu/MenuSeparator.qml
)


install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION "${CMAKE_INSTALL_PREFIX}/frontends/Maia"
)