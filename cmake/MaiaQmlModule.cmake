# Installed QML modules of Maia (Maia.Windows, Maia.Network, ...): a shared library with the types
# and its QML plugin, loaded at run time by every process that imports the module - the shell,
# Maia Settings, app faces - instead of being linked into one program.
#
#   MAIA_QML_BUILD_DIR      where the modules are put in the build tree (one import path for all:
#                           <build>/qml/Maia/Windows, ...), for tests and runs from the build tree
#   MAIA_QML_INSTALL_DIR    where they are installed: <prefix>/<KDE_INSTALL_QMLDIR>
#
#   maia_install_qml_module(<target> URI <uri>)
#       Installs a module made with qt_add_qml_module(<target> ... OUTPUT_DIRECTORY
#       ${MAIA_QML_BUILD_DIR}/<uri as path>): the library to the library directory, the plugin,
#       qmldir and type information to MAIA_QML_INSTALL_DIR/<uri as path>. The plugin finds the
#       library relative to itself, so the installation can move.
#
#   maia_target_qml_import_dir(<target>)
#       Gives <target> the definition MAIA_QML_INSTALL_DIR, for engines to add it as import path
#       (QQmlEngine::addImportPath). The directory is not one Qt searches by default.

# Included from several directories: the variables must be set in each of them (no include_guard)
set(MAIA_QML_BUILD_DIR "${CMAKE_BINARY_DIR}/qml")
set(MAIA_QML_INSTALL_DIR "${KDE_INSTALL_FULL_QMLDIR}")

function(maia_install_qml_module target)
    cmake_parse_arguments(ARG "" "URI" "" ${ARGN})
    if(NOT ARG_URI)
        message(FATAL_ERROR "maia_install_qml_module(${target}): URI is required")
    endif()
    string(REPLACE "." "/" module_path "${ARG_URI}")
    set(build_dir "${MAIA_QML_BUILD_DIR}/${module_path}")
    set(install_dir "${MAIA_QML_INSTALL_DIR}/${module_path}")

    # The C++ classes are not a public API, but the module's tests link the library directly
    set_target_properties(${target} PROPERTIES
        CXX_VISIBILITY_PRESET default
        VISIBILITY_INLINES_HIDDEN OFF
    )

    # <qml dir>/Maia/Windows -> <lib dir>: as many levels up as the URI has parts, plus "qml"
    string(REGEX MATCHALL "/" slashes "/${module_path}")
    list(LENGTH slashes depth)
    file(RELATIVE_PATH qml_to_lib "${MAIA_QML_INSTALL_DIR}" "${KDE_INSTALL_FULL_LIBDIR}")
    set(up "")
    foreach(i RANGE 1 ${depth})
        string(APPEND up "../")
    endforeach()
    # The QML engine looks for lib<plugin>.so; KDECMakeSettings drops the prefix of modules
    set_target_properties(${target}plugin PROPERTIES
        PREFIX "lib"
        INSTALL_RPATH "$ORIGIN/${up}${qml_to_lib}"
    )

    install(TARGETS ${target} LIBRARY DESTINATION "${KDE_INSTALL_FULL_LIBDIR}")
    install(TARGETS ${target}plugin LIBRARY DESTINATION "${install_dir}")
    install(FILES "${build_dir}/qmldir" "${build_dir}/${target}.qmltypes" DESTINATION "${install_dir}")
endfunction()

function(maia_target_qml_import_dir target)
    target_compile_definitions(${target} PRIVATE MAIA_QML_INSTALL_DIR="${MAIA_QML_INSTALL_DIR}")
endfunction()
