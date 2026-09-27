cmake_minimum_required(VERSION 3.16)

# --- Definicja projektu ---
set(MAIA_VERSION 0.1.0)
project(Maia VERSION ${MAIA_VERSION} LANGUAGES CXX)

# --- Ustawienia C++ ---
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- Ustawienia wersji wymaganych pakietów ---
set(QT_MAJOR_VERSION 6)
set(REQUIRED_QT_VERSION 6.10)
set(REQUIRED_KF_VERSION 6.24.0)
set(REQUIRED_PULSEAUDIOQT_VERSION 1.6.0)

# ==============================================================================
# 1. ŁADOWANIE EXTRA CMAKE MODULES (ECM)
# To musi być zrobione jak najwcześniej, żeby mieć dostęp do modułów KDE.
# ==============================================================================
find_package(ECM ${REQUIRED_KF_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})

# ==============================================================================
# 2. STANDARDOWE USTAWIENIA KDE (To naprawia ostrzeżenia)
# Ładujemy KDEInstallDirs PRZED jakimkolwiek find_package(Qt6 ...) w podkatalogach.
# ==============================================================================
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(FeatureSummary)
include(ECMSetupVersion)
include(ECMSourceVersionControl)

# --- Konfiguracja docelowego folderu instalacji (Maia_deploy) ---
# Robimy to po KDEInstallDirs, aby CMake użył Twojego folderu, a nie systemowego /usr/local
if (CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/Maia_deploy/Maia_${PROJECT_VERSION}" CACHE PATH "Install path" FORCE)
endif()

# ==============================================================================
# 3. KONTROLA WERSJI (GIT)
# Zmieniono 'add_definitions' na nowocześniejsze 'add_compile_definitions'
# ==============================================================================
if(${ECM_SOURCE_UNDER_VERSION_CONTROL})
    execute_process(COMMAND git rev-parse --abbrev-ref HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_BRANCH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    execute_process(COMMAND git log -1 --format=%h
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_COMMIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE)

    add_compile_definitions(GIT_COMMIT_HASH="${GIT_COMMIT_HASH}" GIT_BRANCH="${GIT_BRANCH}")
else()
    add_compile_definitions(GIT_COMMIT_HASH="${MAIA_VERSION}" GIT_BRANCH="Stable")
endif()

# ==============================================================================
# 4. DODAWANIE PODKATALOGÓW Z KODEM
# Wewnątrz tych folderów powinieneś teraz używać normalnie find_package(KF6... REQUIRED)
# ==============================================================================
# libraries
add_subdirectory(Maia/BackendLib)
add_subdirectory(Maia/ClientLib)
add_subdirectory(Maia/UILib)

# gnome frontend qml module
add_subdirectory(Maia/GnomeMod)

# xp luna frontend qml module
add_subdirectory(Maia/XPLunaMod)

# cutefish frontend qml module
add_subdirectory(Maia/CutefishMod)

# logger & server applications
add_subdirectory(Maia/LoggerApp)
add_subdirectory(Maia/MaiaServerApp)

# scripts that will be copied while deploy
add_subdirectory(Maia/DeployFiles)

# ==============================================================================
# 5. DOKUMENTACJA I PODSUMOWANIE
# ==============================================================================
add_custom_target(Documentation)
target_sources(Documentation PRIVATE README.md)

# Wypisuje ładną tabelkę na końcu konfiguracji co znaleziono, a czego brakuje
feature_summary(WHAT ALL INCLUDE_QUIET_PACKAGES FATAL_ON_MISSING_REQUIRED_PACKAGES)
