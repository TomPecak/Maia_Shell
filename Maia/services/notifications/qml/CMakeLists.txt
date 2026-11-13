# The QML modules of the notification service, two because they have two kinds of users:
#
#   notifications/  Maia.Notifications         Notification, Notifications: for programs that send
#   center/         Maia.Notifications.Center  NotificationCenter, NotificationsModel,
#                                              NotificationPopups: for shells that show them
#
# The shells' module is a part of the notifications' domain (Maia.<domain>.Center), not a module of
# the service: a module names its domain, never the process behind it.
#
# Both are built on common/ (a static library linked into each): the C++ code of the contract and
# ServiceLink, the connection whose Cap'n Proto runs in its own thread. No user interface: the
# shells and the apps draw notifications in their own style.

include(MaiaCapnProto)
include(MaiaQmlModule)

find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Core Gui Qml)
find_package(KF6 ${REQUIRED_KF_VERSION} REQUIRED COMPONENTS WindowSystem)

qt_add_library(MaiaNotificationsCommon STATIC
    common/ServiceLink.h common/ServiceLink.cpp
    common/NotificationData.h
    common/Contract.h common/Contract.cpp
)
set_target_properties(MaiaNotificationsCommon PROPERTIES POSITION_INDEPENDENT_CODE ON)
maia_capnp_generate_cpp(MaiaNotificationsCommon
    SRC_PREFIX ${CMAKE_CURRENT_SOURCE_DIR}/../contract
    SCHEMAS ${CMAKE_CURRENT_SOURCE_DIR}/../contract/notifications.capnp
)
# The modules use the generated headers and Cap'n Proto themselves
target_include_directories(MaiaNotificationsCommon PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/common
    ${CMAKE_CURRENT_BINARY_DIR}/capnp
)
target_link_libraries(MaiaNotificationsCommon PUBLIC Qt6::Core Maia::CapnProto)
# Cap'n Proto reports errors as exceptions (KDE settings turn them off by default)
kde_target_enable_exceptions(MaiaNotificationsCommon PUBLIC)

add_subdirectory(notifications)
add_subdirectory(center)

if(BUILD_TESTING)
    # Both modules against the real service (without D-Bus), as a program and a shell use them
    find_package(Qt6 ${REQUIRED_QT_VERSION} REQUIRED COMPONENTS Test)
    add_executable(tst_notifications tests/tst_notifications.cpp)
    target_link_libraries(tst_notifications PRIVATE Maia::Notifications Maia::NotificationsCenter Qt6::Test)
    get_target_property(notifications_service maia-notifications-service MAIA_CARGO_BINARY)
    target_compile_definitions(tst_notifications PRIVATE MAIA_NOTIFICATIONS_SERVICE="${notifications_service}")
    add_dependencies(tst_notifications maia-notifications-service)
    add_test(NAME maia-notifications-qml COMMAND tst_notifications)
    set_tests_properties(maia-notifications-qml PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
