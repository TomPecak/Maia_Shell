# Cap'n Proto contracts in Maia: code generation from schemas, for C++ targets and for cargo builds.
#
#   maia_capnp_generate_cpp(<target>
#       SRC_PREFIX <directory>            the schemas' root; generated files keep the paths below it
#       SCHEMAS <file.capnp>...
#   )
#       Generates the C++ code of the schemas in the build tree and adds it to <target>: the
#       sources, the include directory of the generated headers and the link to Maia::CapnProto.
#
#   maia_capnp_cargo_environment(<env variable> <depends variable>)
#       For Rust crates whose build.rs compiles schemas: sets <env variable> to the environment
#       assignments MAIA_CAPNP_EXECUTABLE=... and MAIA_CAPNP_IMPORT_DIR=..., and <depends variable>
#       to the targets that must be built before cargo runs (see maia_add_cargo_executable).
#
# The compiler and the libraries come from 3rdparty/capnproto (built there, or installed with
# MAIA_USE_SYSTEM_CAPNPROTO), which must be added before these functions are called. The compiler
# runs with --no-standard-import: only the schemas of that Cap'n Proto are visible, never another
# version installed in /usr/include or /usr/local/include.

include_guard(GLOBAL)

# Reads a global property published by 3rdparty/capnproto (MAIA_CAPNP_TOOL_TARGETS may be empty)
function(_maia_capnp_get variable property)
    get_property(published GLOBAL PROPERTY ${property} SET)
    if(NOT published)
        message(FATAL_ERROR "${property} is not set: add_subdirectory(3rdparty) must come before the users of Cap'n Proto")
    endif()
    get_property(value GLOBAL PROPERTY ${property})
    set(${variable} "${value}" PARENT_SCOPE)
endfunction()

function(maia_capnp_generate_cpp target)
    cmake_parse_arguments(ARG "" "SRC_PREFIX" "SCHEMAS" ${ARGN})
    if(NOT ARG_SRC_PREFIX OR NOT ARG_SCHEMAS)
        message(FATAL_ERROR "maia_capnp_generate_cpp(${target}): SRC_PREFIX and SCHEMAS are required")
    endif()
    _maia_capnp_get(capnp MAIA_CAPNP_EXECUTABLE)
    _maia_capnp_get(capnpc_cxx MAIA_CAPNPC_CXX_EXECUTABLE)
    _maia_capnp_get(import_dir MAIA_CAPNP_IMPORT_DIR)
    _maia_capnp_get(tool_targets MAIA_CAPNP_TOOL_TARGETS)

    get_filename_component(prefix "${ARG_SRC_PREFIX}" ABSOLUTE)
    set(output_dir "${CMAKE_CURRENT_BINARY_DIR}/capnp")
    # Exists before the first build step that uses it as an include directory
    file(MAKE_DIRECTORY "${output_dir}")

    set(generated)
    foreach(schema ${ARG_SCHEMAS})
        get_filename_component(schema "${schema}" ABSOLUTE)
        file(RELATIVE_PATH relative "${prefix}" "${schema}")
        if(relative MATCHES "^\\.\\./")
            message(FATAL_ERROR "maia_capnp_generate_cpp(${target}): ${schema} is not below ${prefix}")
        endif()
        set(base "${output_dir}/${relative}")
        add_custom_command(
            OUTPUT "${base}.c++" "${base}.h"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${output_dir}"
            COMMAND "${capnp}" compile --no-standard-import -I "${import_dir}" -I "${prefix}"
                    --src-prefix "${prefix}" "-o${capnpc_cxx}:${output_dir}" "${schema}"
            DEPENDS "${schema}" ${tool_targets}
            COMMENT "Generating C++ code of the Cap'n Proto schema ${relative}"
            VERBATIM
        )
        list(APPEND generated "${base}.c++" "${base}.h")
    endforeach()

    target_sources(${target} PRIVATE ${generated})
    # Generated code is not ours to fix
    set_source_files_properties(${generated} TARGET_DIRECTORY ${target} PROPERTIES COMPILE_OPTIONS "-w")
    target_include_directories(${target} PRIVATE "${output_dir}")
    target_link_libraries(${target} PRIVATE Maia::CapnProto)
endfunction()

function(maia_capnp_cargo_environment env_variable depends_variable)
    _maia_capnp_get(capnp MAIA_CAPNP_EXECUTABLE)
    _maia_capnp_get(import_dir MAIA_CAPNP_IMPORT_DIR)
    _maia_capnp_get(tool_targets MAIA_CAPNP_TOOL_TARGETS)
    set(${env_variable} "MAIA_CAPNP_EXECUTABLE=${capnp}" "MAIA_CAPNP_IMPORT_DIR=${import_dir}" PARENT_SCOPE)
    set(${depends_variable} ${tool_targets} PARENT_SCOPE)
endfunction()
