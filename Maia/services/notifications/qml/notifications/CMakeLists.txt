# QML module Maia.Notifications: Notification (one notification of a program, declaratively), Job
# (a long operation of a program, with its progress) and Notifications (whether the service runs),
# over the Notifier of the notification service.

qt_add_library(MaiaNotifications SHARED)
add_library(Maia::Notifications ALIAS MaiaNotifications)

qt_add_qml_module(MaiaNotifications
    URI Maia.Notifications
    VERSION 1.0
    OUTPUT_DIRECTORY ${MAIA_QML_BUILD_DIR}/Maia/Notifications
    SOURCES
        NotifierConnection.h NotifierConnection.cpp
        Notification.h Notification.cpp
        Job.h Job.cpp
        Notifications.h Notifications.cpp
)

target_include_directories(MaiaNotifications PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(MaiaNotifications
    PUBLIC Qt6::Core Qt6::Gui Qt6::Qml
    PRIVATE MaiaNotificationsCommon KF6::WindowSystem
)
# Its headers use the plain values of common/NotificationData.h
target_include_directories(MaiaNotifications PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../common)

maia_install_qml_module(MaiaNotifications URI Maia.Notifications)
