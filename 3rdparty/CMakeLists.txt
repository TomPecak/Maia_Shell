# External dependencies built together with Maia (see README.md).
#
# Each dependency has its own directory: upstream/ holds the unchanged source of a release, the
# CMakeLists.txt next to it builds that source for Maia and publishes it under a Maia name
# (e.g. Maia::CapnProto). The rest of the project links only to those names, so it does not care
# whether a dependency was built here or taken from the system.

# --- Settings for third-party code (this directory and below only) ---
# Maia's compiler settings (KDECompilerSettings: no exceptions, strict warnings, Qt definitions) are
# made for Maia's own code. Third-party code is built the way its authors expect it to be built.

# Static libraries, linked into the Maia programs: nothing extra to install or ship
set(BUILD_SHARED_LIBS OFF)
# Usable in executables (PIE) and in shared libraries (QML plugins) alike
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# The tests of the dependencies are run by their authors, not by Maia's ctest
set(BUILD_TESTING OFF)
# KDECMakeSettings puts the directory of every target on its own and its users' include path.
# Libraries may have headers named like system ones (Cap'n Proto: kj/string.h), which would then
# hide <string.h>. Its Qt code generators (moc, rcc, uic) have nothing to do here either.
set(CMAKE_INCLUDE_CURRENT_DIR OFF)
set(CMAKE_INCLUDE_CURRENT_DIR_IN_INTERFACE OFF)
set(CMAKE_AUTOMOC OFF)
set(CMAKE_AUTORCC OFF)
set(CMAKE_AUTOUIC OFF)
# C++ libraries report errors with exceptions; KDE turns them off by default
string(REPLACE "-fno-exceptions" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
string(APPEND CMAKE_CXX_FLAGS " -fexceptions")
# Warnings in code we do not change are noise; consumers see its headers as system headers
add_compile_options(-w)

add_subdirectory(capnproto)
