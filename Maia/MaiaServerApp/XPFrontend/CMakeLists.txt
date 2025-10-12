qt_standard_project_setup(REQUIRES ${REQUIRED_QT_VERSION})

qt_add_library(XPFrontend STATIC)

set(XPFRONTEND_QML_FILES
    Main.qml
    TaskbarButton.qml
    style_items/TiledImage.qml
    style_items/XPMenu.qml
    style_items/XPMenuItem.qml
    style_items/XPMenuSeparator.qml
    style_items/TiledImageVertical.qml
    windows/AppMenuWindow.qml
    windows/SystemVolumeWindow.qml
    contents/AppMenuContent.qml
    contents/Clock3DContent.qml
    TurnOffContent.qml
    LogoutContent.qml
    WallpaperContent.qml
    TaskbarContent.qml
    mask/MainMask.qml
    mask/WindowOverlay.qml
    windows/Clock3DWindow.qml
    popups/AppMenuPopup.qml
    contents/SystemVolumeContent.qml
    popups/SystemVolumePopup.qml
    components/LicenseWarning.qml
)

set (KWIN_XBOOMER_THEME
    assets/kwin_themes/XBoomer/alldesktops.svg
    assets/kwin_themes/XBoomer/close.svg
    assets/kwin_themes/XBoomer/decoration.svg
    assets/kwin_themes/XBoomer/LICENSE
    assets/kwin_themes/XBoomer/maximize.svg
    assets/kwin_themes/XBoomer/metadata.desktop
    assets/kwin_themes/XBoomer/minimize.svg
    assets/kwin_themes/XBoomer/restore.svg
    assets/kwin_themes/XBoomer/shade.svg
    assets/kwin_themes/XBoomer/XBoomerrc
)




# Ikony Oxygen
file(GLOB_RECURSE OXYGEN_ICON_THEME CONFIGURE_DEPENDS
     RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
     #CONFIGURE_DEPENDS
     "assets/icons/oxygen/*")

 message("[WARNING], collecting oxygen icon files in this way slows down the cmake configuration process a lot, maybe this should be changed somehow ")

 # Ikony Hicolor
 file(GLOB_RECURSE HICOLOR_ICON_THEME CONFIGURE_DEPENDS
      RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
      #CONFIGURE_DEPENDS
      "assets/icons/hicolor/*")

   message("[WARNING], collecting hicolor icon files in this way slows down the cmake configuration process a lot, maybe this should be changed somehow ")

qt_add_resources(XPFrontend "XPFrontendAssets"
    PREFIX "/"
    FILES
    assets/images/app_list/app_list_right_border.png
    assets/images/app_list/search_separator.png
    assets/images/images/dialog_log_off_logoff_button_hover.bmp
    assets/images/images/dialog_log_off_logoff_button_normal.bmp
    assets/images/images/dialog_log_off_logoff_button_pressed.bmp
    assets/images/images/dialog_log_off_switchuser_button_normal.bmp
    assets/images/images/dialog_log_off_switchuser_button_pressed.bmp
    assets/images/images/log_off_dialog.bmp
    assets/images/images/start_hover.bmp
    assets/images/images/start_normal.bmp
    assets/images/images/start_pressed.bmp
    assets/images/images/xp_fhd.jpg
    assets/images/start_menu/all_programs_button_hover.png
    assets/images/start_menu/all_programs_button_normal.png
    assets/images/start_menu/start_menu.png
    assets/images/system_volume_dialog/mute_checkbox/mute_hover.bmp
    assets/images/system_volume_dialog/mute_checkbox/mute_hover_checked.bmp
    assets/images/system_volume_dialog/mute_checkbox/mute_normal.bmp
    assets/images/system_volume_dialog/mute_checkbox/mute_normal_checked.bmp
    assets/images/system_volume_dialog/mute_checkbox/mute_pressed.bmp
    assets/images/system_volume_dialog/mute_checkbox/mute_pressed_checked.bmp
    assets/images/system_volume_dialog/slider/slider_background_bottom.bmp
    assets/images/system_volume_dialog/slider/slider_background_middle.bmp
    assets/images/system_volume_dialog/slider/slider_background_top.bmp
    assets/images/system_volume_dialog/slider/slider_handle_hover.bmp
    assets/images/system_volume_dialog/slider/slider_handle_normal.bmp
    assets/images/system_volume_dialog/slider/slider_handle_pressed.bmp
    assets/images/system_volume_dialog/bottom_left.bmp
    assets/images/system_volume_dialog/bottom_middle.bmp
    assets/images/system_volume_dialog/bottom_right.bmp
    assets/images/system_volume_dialog/middle_left.bmp
    assets/images/system_volume_dialog/middle_middle.bmp
    assets/images/system_volume_dialog/middle_right.bmp
    assets/images/system_volume_dialog/top_left.bmp
    assets/images/system_volume_dialog/top_middle.bmp
    assets/images/system_volume_dialog/top_right.bmp
    assets/images/taskbar/background_button_hover/left_bottom.bmp
    assets/images/taskbar/background_button_hover/left_middle.bmp
    assets/images/taskbar/background_button_hover/left_top.bmp
    assets/images/taskbar/background_button_hover/middle_bottom.bmp
    assets/images/taskbar/background_button_hover/middle_middle.bmp
    assets/images/taskbar/background_button_hover/middle_top.bmp
    assets/images/taskbar/background_button_hover/right_bottom.bmp
    assets/images/taskbar/background_button_hover/right_middle.bmp
    assets/images/taskbar/background_button_hover/right_top.bmp
    assets/images/taskbar/background_button_normal/bottom_left.png
    assets/images/taskbar/background_button_normal/bottom_middle.png
    assets/images/taskbar/background_button_normal/bottom_right.png
    assets/images/taskbar/background_button_normal/middle_left.png
    assets/images/taskbar/background_button_normal/middle_middle.bmp
    assets/images/taskbar/background_button_normal/middle_right.png
    assets/images/taskbar/background_button_normal/top_left.png
    assets/images/taskbar/background_button_normal/top_middle.png
    assets/images/taskbar/background_button_normal/top_right.png
    assets/images/taskbar/background_button_pressed/left_bottom.bmp
    assets/images/taskbar/background_button_pressed/left_middle.bmp
    assets/images/taskbar/background_button_pressed/left_top.bmp
    assets/images/taskbar/background_button_pressed/middle_bottom.bmp
    assets/images/taskbar/background_button_pressed/middle_middle.bmp
    assets/images/taskbar/background_button_pressed/middle_top.bmp
    assets/images/taskbar/background_button_pressed/right_bottom.bmp
    assets/images/taskbar/background_button_pressed/right_middle.bmp
    assets/images/taskbar/background_button_pressed/right_top.bmp
    assets/images/taskbar/background_button_pressed_hover/left_bottom.bmp
    assets/images/taskbar/background_button_pressed_hover/left_middle.bmp
    assets/images/taskbar/background_button_pressed_hover/left_top.bmp
    assets/images/taskbar/background_button_pressed_hover/middle_bottom.bmp
    assets/images/taskbar/background_button_pressed_hover/middle_middle.bmp
    assets/images/taskbar/background_button_pressed_hover/middle_top.bmp
    assets/images/taskbar/background_button_pressed_hover/right_bottom.bmp
    assets/images/taskbar/background_button_pressed_hover/right_middle.bmp
    assets/images/taskbar/background_button_pressed_hover/right_top.bmp
    assets/images/taskbar/notification_area/speaker.bmp
    assets/images/taskbar/notification_area/speaker.png
    assets/images/clock_background.bmp assets/images/dialog_turn_off_cancel_button_hover.png
    assets/images/dialog_turn_off_cancel_button_normal.png
    assets/images/dialog_turn_off_cancel_button_pressed.png
    assets/images/dialog_turn_off_power_button_normal.png
    assets/images/dialog_turn_off_power_button_pressed.png
    assets/images/dialog_turn_off_restart_button_hover.png
    assets/images/dialog_turn_off_restart_button_normal.png
    assets/images/dialog_turn_off_restart_button_pressed.png
    assets/images/menu_start_logout_hover.png
    assets/images/menu_start_logout_normal.png
    assets/images/power_off_button.png
    assets/images/power_off_button_hover.png
    assets/images/separator.bmp
    assets/images/task_bar_background.bmp
    assets/images/taskpanel_separator.bmp
    assets/images/turn_off_dialog.png
    #assets/images/arrow.svg
    #assets/images/arrow_pixel_art.svg
    assets/images/arrow_pixel_art.png
    assets/images/license_warning.svg

    assets/fonts/tahoma.ttf
    assets/fonts/tahomabd.ttf
    assets/fonts/NeverMindHandwriting-Regular.ttf


    ${KWIN_XBOOMER_THEME}
    ${XPFRONTEND_QML_FILES}
    ${OXYGEN_ICON_THEME}
    ${HICOLOR_ICON_THEME}
)

qt_add_qml_module(XPFrontend
    URI XPFrontend
    VERSION 1.0

    QML_FILES
    ${XPFRONTEND_QML_FILES}
)



