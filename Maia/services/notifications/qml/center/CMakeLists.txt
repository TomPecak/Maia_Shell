# QML module Maia.Notifications.Center: NotificationCenter (do not disturb, actions, replies),
# NotificationsModel (the list), NotificationGroupsModel (the list by application) and NotificationPopupsModel (the popups now, with their clocks), over the
# NotificationCenter of the notification service. For shells.

qt_add_library(MaiaNotificationsCenter SHARED)
add_library(Maia::NotificationsCenter ALIAS MaiaNotificationsCenter)

qt_add_qml_module(MaiaNotificationsCenter
    URI Maia.Notifications.Center
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Notifications/Center
    SOURCES
        CenterConnection.h CenterConnection.cpp
        NotificationRoles.h NotificationRoles.cpp
        NotificationCenter.h NotificationCenter.cpp
        NotificationsModel.h NotificationsModel.cpp
        NotificationGroupsModel.h NotificationGroupsModel.cpp
        NotificationPopupsModel.h NotificationPopupsModel.cpp
        JobsModel.h JobsModel.cpp
)

target_include_directories(MaiaNotificationsCenter PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaNotificationsCenter
    PUBLIC Qt6::Core Qt6::Gui Qt6::Qml
    PRIVATE MaiaNotificationsCommon KF6::WindowSystem
)
# Its headers use the plain values of common/NotificationData.h
target_include_directories(MaiaNotificationsCenter PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../common)

maia_install_qml_module(MaiaNotificationsCenter URI Maia.Notifications.Center)
