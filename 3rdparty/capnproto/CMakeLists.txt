# Cap'n Proto (C++): serialization and RPC of the contracts between Maia services and their clients.
# Version, origin and how to update: README.md.
#
# By default it is built from upstream/ (static libraries, plus the schema compiler for the build).
# With MAIA_USE_SYSTEM_CAPNPROTO=ON an installed Cap'n Proto is used instead (distribution packages).
#
# Published for the rest of Maia, the same in both cases:
#   Maia::CapnProto              link target: capnp-rpc, capnp, kj-async, kj
#   global properties            MAIA_CAPNP_EXECUTABLE       the schema compiler `capnp`
#                                MAIA_CAPNPC_CXX_EXECUTABLE  its C++ plugin `capnpc-c++`
#                                MAIA_CAPNP_IMPORT_DIR       standard schemas (capnp/c++.capnp, ...)
#                                MAIA_CAPNP_TOOL_TARGETS     targets that build the two programs
# They are read by cmake/MaiaCapnProto.cmake, which is what Maia's own CMake files use.

option(MAIA_USE_SYSTEM_CAPNPROTO "Use an installed Cap'n Proto (C++) instead of 3rdparty/capnproto/upstream" OFF)

set(capnp_libraries CapnProto::capnp-rpc CapnProto::capnp CapnProto::kj-async CapnProto::kj)

if(MAIA_USE_SYSTEM_CAPNPROTO)
    find_package(CapnProto 1.0 CONFIG REQUIRED)
    # Imported targets are local to this directory unless promoted
    foreach(target ${capnp_libraries} CapnProto::capnp_tool CapnProto::capnpc_cpp)
        set_target_properties(${target} PROPERTIES IMPORTED_GLOBAL TRUE)
    endforeach()
    set(capnp_executable "${CAPNP_EXECUTABLE}")
    set(capnpc_cxx_executable "${CAPNPC_CXX_EXECUTABLE}")
    set(capnp_import_dir "${CAPNP_INCLUDE_DIRECTORY}")
    set(capnp_tool_targets "")
    message(STATUS "Cap'n Proto: installed ${CapnProto_VERSION} (${CapnProto_DIR})")
else()
    # Cap'n Proto requires the GNU extensions of C++ (it checks it), KDE turns them off
    set(CMAKE_CXX_EXTENSIONS ON)
    # Only what Maia uses: no TLS (OpenSSL) and no compression (zlib), so no extra dependencies
    set(WITH_OPENSSL OFF CACHE STRING "Cap'n Proto (3rdparty): build libkj-tls with OpenSSL")
    set(WITH_ZLIB OFF CACHE STRING "Cap'n Proto (3rdparty): build libkj-gzip with zlib")

    # EXCLUDE_FROM_ALL: only the targets Maia links to (and the compiler) get built, and none of the
    # install rules of Cap'n Proto run on `cmake --install`. SYSTEM: its headers do not produce
    # warnings in Maia's code.
    add_subdirectory(upstream EXCLUDE_FROM_ALL SYSTEM)

    set(capnp_executable "$<TARGET_FILE:capnp_tool>")
    set(capnpc_cxx_executable "$<TARGET_FILE:capnpc_cpp>")
    set(capnp_import_dir "${CMAKE_CURRENT_SOURCE_DIR}/upstream/src")
    set(capnp_tool_targets capnp_tool capnpc_cpp)

    file(STRINGS upstream/CMakeLists.txt version_line REGEX "^set\\(VERSION ")
    string(REGEX REPLACE "^set\\(VERSION ([^)]*)\\).*" "\\1" capnp_version "${version_line}")
    message(STATUS "Cap'n Proto: bundled ${capnp_version} (3rdparty/capnproto/upstream)")
endif()

add_library(MaiaCapnProto INTERFACE)
add_library(Maia::CapnProto ALIAS MaiaCapnProto)
target_link_libraries(MaiaCapnProto INTERFACE ${capnp_libraries})

set_property(GLOBAL PROPERTY MAIA_CAPNP_EXECUTABLE "${capnp_executable}")
set_property(GLOBAL PROPERTY MAIA_CAPNPC_CXX_EXECUTABLE "${capnpc_cxx_executable}")
set_property(GLOBAL PROPERTY MAIA_CAPNP_IMPORT_DIR "${capnp_import_dir}")
set_property(GLOBAL PROPERTY MAIA_CAPNP_TOOL_TARGETS "${capnp_tool_targets}")
