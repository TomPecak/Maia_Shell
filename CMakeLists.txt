cmake_minimum_required(VERSION 3.16)

set(KDE_INSTALL_PREFIX "$ENV{HOME}/kde/usr/lib/x86_64-linux-gnu/cmake")

set(KF6Codecs_DIR ${KDE_INSTALL_PREFIX}/KF6Codecs)
set(KF6ColorScheme_DIR ${KDE_INSTALL_PREFIX}/KF6ColorScheme)
set(KF6ConfigWidgets_DIR ${KDE_INSTALL_PREFIX}/KF6ConfigWidgets)
set(KF6Config_DIR ${KDE_INSTALL_PREFIX}/KF6Config)
set(KF6CoreAddons_DIR ${KDE_INSTALL_PREFIX}/KF6CoreAddons)
set(KF6DBusAddons_DIR ${KDE_INSTALL_PREFIX}/KF6DBusAddons)
set(KF6Declarative_DIR ${KDE_INSTALL_PREFIX}/KF6Declarative)
set(KF6DocTools_DIR ${KDE_INSTALL_PREFIX}/KF6DocTools)
set(KF6GlobalAccel_DIR ${KDE_INSTALL_PREFIX}/KF6GlobalAccel)
set(KF6I18n_DIR ${KDE_INSTALL_PREFIX}/KF6I18n)
set(KF6KCMUtils_DIR ${KDE_INSTALL_PREFIX}/KF6KCMUtils)
set(KF6Package_DIR ${KDE_INSTALL_PREFIX}/KF6Package)
set(KF6PulseAudioQt_DIR ${KDE_INSTALL_PREFIX}/KF6PulseAudioQt)
set(KF6StatusNotifierItem_DIR ${KDE_INSTALL_PREFIX}/KF6StatusNotifierItem)
set(KF6Svg_DIR ${KDE_INSTALL_PREFIX}/KF6Svg)
set(KF6WidgetsAddons_DIR ${KDE_INSTALL_PREFIX}/KF6WidgetsAddons)
set(KF6WindowSystem_DIR ${KDE_INSTALL_PREFIX}/KF6WindowSystem)
set(KF6i18n_DIR ${KDE_INSTALL_PREFIX}/KF6I18n)
set(Plasma_DIR ${KDE_INSTALL_PREFIX}/Plasma)

# set(CMAKE_PREFIX_PATH ${HOME_DIR}/kde/usr/lib/x86_64-linux-gnu/cmake;${CMAKE_PREFIX_PATH})
# set(CMAKE_PREFIX_PATH ${HOME_DIR}/kde/usr/lib/cmake;${CMAKE_PREFIX_PATH})


set(MAIA_VERSION 0.1.0)
project(Maia VERSION ${MAIA_VERSION} LANGUAGES CXX)

# set project deploy directory to  /{HOME}/Maia_deploy/Maia_version
set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/Maia_deploy/Maia_${PROJECT_VERSION}")
set(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT FALSE)  # This line prevents include(KDEInstallDirs) from changing CMAKE_INSTALL_PREFIX


set(QT_MAJOR_VERSION 6)

set(REQUIRED_QT_VERSION 6.8)
set(REQUIRED_KF_VERSION 6.2.0)
set(REQUIRED_PULSEAUDIOQT_VERSION 1.6.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)


find_package(ECM ${REQUIRED_KF_VERSION} NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH})


include(ECMSourceVersionControl)
include(ECMSetupVersion)

if(${ECM_SOURCE_UNDER_VERSION_CONTROL})
    execute_process(COMMAND git rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    # Get the latest abbreviated commit hash of the working branch
    execute_process(COMMAND git log -1 --format=%h
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_COMMIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    add_definitions(-DGIT_COMMIT_HASH="${GIT_COMMIT_HASH}")
    add_definitions(-DGIT_BRANCH="${GIT_BRANCH}")

else()
    add_definitions(-DGIT_COMMIT_HASH="${MAIA_VERSION}")
    add_definitions(-DGIT_BRANCH="Stable")
endif()



# backend Library
add_subdirectory(Maia/BackendLib/)

add_subdirectory(Maia/MaiaClientLib/)

# logger application
add_subdirectory(Maia/LoggerApp/)

# gnome frontend qml module
add_subdirectory(Maia/GnomeMod/)

# xp luna frontend qml module
add_subdirectory(Maia/XPLunaMod/)

# cutefish frontend qml module
add_subdirectory(Maia/CutefishMod/)

add_subdirectory(Maia/MaiaServerApp/)

# scripts thats will be copied while deploy
add_subdirectory(Maia/DeployFiles/)

#add_subdirectory(Experimental/gtk_simple_app/)

add_custom_target(Documentation)
target_sources(Documentation PRIVATE
    README.md
    CONTRIBUTING.md
)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)

