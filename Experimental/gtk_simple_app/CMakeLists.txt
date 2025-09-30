cmake_minimum_required(VERSION 3.16)

project(gtk_simple_app LANGUAGES C)

# Find GTK 4
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK4 REQUIRED gtk4)

# Add linking and compilation flags for GTK 4
include_directories(${GTK4_INCLUDE_DIRS})
link_directories(${GTK4_LIBRARY_DIRS})
add_definitions(${GTK4_CFLAGS_OTHER})


add_executable(gtk_simple_app main.c)


# Link target with gtk+ libs
target_link_libraries(gtk_simple_app ${GTK4_LIBRARIES})

include(GNUInstallDirs)
install(TARGETS gtk_simple_app
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
