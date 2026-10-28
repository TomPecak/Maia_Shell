# Building Rust programs (cargo) as part of a CMake build, without extra CMake modules.
#
#   maia_add_cargo_executable(<target>
#       MANIFEST <path to Cargo.toml>
#       [BINARY <name of the cargo binary>]       default: <target>
#       [INSTALL_DESTINATION <directory>]         e.g. ${CMAKE_INSTALL_LIBEXECDIR}/<app>
#       [ENVIRONMENT <NAME=value>...]             for cargo and build.rs (generator expressions allowed)
#       [DEPENDS <target>...]                     built before cargo runs (e.g. a code generator)
#   )
#
# Adds the target <target> (part of `all`) that runs `cargo build`, and sets its property
# MAIA_CARGO_BINARY to the path of the built program. With INSTALL_DESTINATION the program is
# installed there; with BUILD_TESTING (include(CTest)) `cargo test` becomes a CTest test.
#
# - Cargo decides itself what to rebuild, so the target runs cargo on every build
#   (a build with nothing to do takes about 0.1 s).
# - CMAKE_BUILD_TYPE Debug uses the cargo dev profile, any other type --release.
# - All crates share one target directory in the build tree (MAIA_CARGO_TARGET_DIR): common
#   dependencies (tokio, capnp) are compiled once and nothing is written into the source tree.
# - Crates with Cap'n Proto schemas get the schema compiler through ENVIRONMENT and DEPENDS, see
#   maia_capnp_cargo_environment in MaiaCapnProto.cmake.
# - MAIA_CARGO_JOBS limits the parallel rustc processes (little RAM: 15 GB, no swap). Cargo runs in
#   the console pool of Ninja, next to the C++ jobs, so the memory peak is cargo + `cmake --build -j`.
#
# When this is not enough (dependencies between crates and C++ targets, several configurations
# of a multi-config generator), the standard next step is Corrosion (corrosion_import_crate).

include_guard(GLOBAL)

find_program(MAIA_CARGO cargo HINTS "$ENV{HOME}/.cargo/bin" REQUIRED)
set(MAIA_CARGO_JOBS 3 CACHE STRING "Parallel jobs of cargo (rustc processes)")
set(MAIA_CARGO_TARGET_DIR "${CMAKE_BINARY_DIR}/cargo" CACHE PATH "Shared target directory of all cargo builds")

function(maia_add_cargo_executable target)
    cmake_parse_arguments(ARG "" "MANIFEST;BINARY;INSTALL_DESTINATION" "ENVIRONMENT;DEPENDS" ${ARGN})
    if(NOT ARG_MANIFEST)
        message(FATAL_ERROR "maia_add_cargo_executable(${target}): MANIFEST is required")
    endif()
    if(NOT ARG_BINARY)
        set(ARG_BINARY ${target})
    endif()
    get_filename_component(manifest "${ARG_MANIFEST}" ABSOLUTE)
    get_filename_component(crate_dir "${manifest}" DIRECTORY)

    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(profile_flags "")
        set(profile_dir debug)
    else()
        set(profile_flags --release)
        set(profile_dir release)
    endif()
    set(binary "${MAIA_CARGO_TARGET_DIR}/${profile_dir}/${ARG_BINARY}")
    set(cargo ${CMAKE_COMMAND} -E env CARGO_TARGET_DIR=${MAIA_CARGO_TARGET_DIR} ${ARG_ENVIRONMENT} ${MAIA_CARGO})

    add_custom_target(${target} ALL
        COMMAND ${cargo} build ${profile_flags} --jobs ${MAIA_CARGO_JOBS}
                --manifest-path ${manifest} --bin ${ARG_BINARY}
        BYPRODUCTS ${binary}
        WORKING_DIRECTORY ${crate_dir}
        USES_TERMINAL
        COMMENT "cargo build ${ARG_BINARY} (${profile_dir})"
        VERBATIM
    )
    set_target_properties(${target} PROPERTIES MAIA_CARGO_BINARY ${binary})
    if(ARG_DEPENDS)
        add_dependencies(${target} ${ARG_DEPENDS})
    endif()

    if(ARG_INSTALL_DESTINATION)
        install(PROGRAMS ${binary} DESTINATION ${ARG_INSTALL_DESTINATION})
    endif()

    if(BUILD_TESTING)
        add_test(NAME ${target}-cargo-test
                 COMMAND ${cargo} test ${profile_flags} --jobs ${MAIA_CARGO_JOBS} --manifest-path ${manifest}
                 WORKING_DIRECTORY ${crate_dir})
    endif()
endfunction()
