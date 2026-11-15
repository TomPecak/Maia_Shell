# QML module Maia.Notifications.Settings: NotificationSettings (do not disturb, the lock screen) and
# AppNotificationsModel (each application on or off), over the NotificationSettings of the
# notification service. For Maia Settings: rules only, it never sees a notification.

qt_add_library(MaiaNotificationsSettings SHARED)
add_library(Maia::NotificationsSettings ALIAS MaiaNotificationsSettings)

qt_add_qml_module(MaiaNotificationsSettings
    URI Maia.Notifications.Settings
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Notifications/Settings
    SOURCES
        SettingsConnection.h SettingsConnection.cpp
        NotificationSettings.h NotificationSettings.cpp
        AppNotificationsModel.h AppNotificationsModel.cpp
)

target_include_directories(MaiaNotificationsSettings PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaNotificationsSettings
    PUBLIC Qt6::Core Qt6::Qml
    PRIVATE MaiaNotificationsCommon
)
# Its headers use the plain values of common/NotificationData.h
target_include_directories(MaiaNotificationsSettings PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../common)

maia_install_qml_module(MaiaNotificationsSettings URI Maia.Notifications.Settings)
