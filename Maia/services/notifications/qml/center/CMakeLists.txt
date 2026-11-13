# QML module Maia.NotificationCenter: NotificationCenter (do not disturb, actions, replies),
# NotificationsModel (the list) and NotificationPopups (the popups now, with their clocks), over the
# NotificationCenter of the notification service. For shells.

qt_add_library(MaiaNotificationCenter SHARED)
add_library(Maia::NotificationCenter ALIAS MaiaNotificationCenter)

qt_add_qml_module(MaiaNotificationCenter
    URI Maia.NotificationCenter
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/NotificationCenter
    SOURCES
        CenterConnection.h CenterConnection.cpp
        NotificationRoles.h NotificationRoles.cpp
        NotificationCenter.h NotificationCenter.cpp
        NotificationsModel.h NotificationsModel.cpp
        NotificationPopups.h NotificationPopups.cpp
)

target_include_directories(MaiaNotificationCenter PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaNotificationCenter
    PUBLIC Qt6::Core Qt6::Gui Qt6::Qml
    PRIVATE MaiaNotificationsCommon KF6::WindowSystem
)
# Its headers use the plain values of common/NotificationData.h
target_include_directories(MaiaNotificationCenter PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../common)

maia_install_qml_module(MaiaNotificationCenter URI Maia.NotificationCenter)
