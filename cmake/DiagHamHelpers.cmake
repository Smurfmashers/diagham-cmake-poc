# ============================================================================
# DiagHamHelpers.cmake: helpers for the DiagHam CMake build
# ============================================================================
#
# These macros let each src/<subdir>/CMakeLists.txt be a one-liner, e.g.:
#
#    diagham_add_library(Matrix
#        SOURCES Matrix.cc RealSymmetricMatrix.cc ...
#    )
#
# They produce the same static libraries as the autotools build:
# Base/src/<subdir>/lib<NAME>.a or src/<subdir>/lib<NAME>.a, with names
# matching the autotools targets one-for-one.
#
# This is deliberately a thin layer over add_library / add_executable,
# the modernisation should *not* hide CMake from contributors, only
# make repetitive boilerplate go away.
# ============================================================================

# A registry of all DiagHam libraries built so far, so executables can
# easily link against "everything" without enumerating per-binary.
set_property(GLOBAL PROPERTY DIAGHAM_ALL_LIBS "")

function(diagham_add_library target_name)
    cmake_parse_arguments(ARG "" "" "SOURCES" ${ARGN})

    if(NOT ARG_SOURCES)
        message(FATAL_ERROR "diagham_add_library(${target_name}): no SOURCES given")
    endif()

    add_library(${target_name} STATIC ${ARG_SOURCES})

    # Make the static archive output as lib<target>.a (which matches autotools).
    # CMake does this by default on Linux, but be explicit so the matching is
    # unambiguous when comparing binaries to the autotools build.
    set_target_properties(${target_name} PROPERTIES
        ARCHIVE_OUTPUT_NAME ${target_name}
        POSITION_INDEPENDENT_CODE ON
    )

    # Track this library globally
    get_property(libs GLOBAL PROPERTY DIAGHAM_ALL_LIBS)
    list(APPEND libs ${target_name})
    set_property(GLOBAL PROPERTY DIAGHAM_ALL_LIBS "${libs}")
endfunction()


# A program is a single-file executable that links against (essentially)
# every static library. We rely on the linker's dead-stripping rather
# than enumerating per-binary LDADD lists, the autotools build already
# does this implicitly via the duplicated -l flags.
function(diagham_add_program target_name source)
    if(NOT DIAGHAM_BUILD_PROGRAMS)
        return()
    endif()

    add_executable(${target_name} ${source})

    # Link against all libraries built so far. The order matters because of
    # mutual recursion between Architecture and ArchitectureOperation, so we
    # link with --start-group/--end-group on GNU ld.
    get_property(all_libs GLOBAL PROPERTY DIAGHAM_ALL_LIBS)

    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        target_link_libraries(${target_name} PRIVATE
            -Wl,--start-group
            ${all_libs}
            -Wl,--end-group
        )
    else()
        target_link_libraries(${target_name} PRIVATE ${all_libs})
    endif()

    # Common system libs that DiagHam uses everywhere
    target_link_libraries(${target_name} PRIVATE m)

    if(DIAGHAM_USE_SMP)
        target_link_libraries(${target_name} PRIVATE Threads::Threads)
    endif()
    if(DIAGHAM_USE_LAPACK)
        target_link_libraries(${target_name} PRIVATE ${LAPACK_LIBRARIES})
    endif()
    if(DIAGHAM_USE_MPI)
        target_link_libraries(${target_name} PRIVATE MPI::MPI_CXX)
    endif()
endfunction()


# Discover and add every .cc in a Programs/ subdirectory as its own binary.
# This is more robust than enumerating them: adding a new program means
# just dropping a .cc file in the directory, no Makefile.am editing.
# That's one concrete win of the CMake migration.
#
# Some upstream program names collide across directories (e.g. QHEBosonsDelta
# exists in both FQHE/src/Programs/FQHEOnSphere and FQHE/src/Programs/FQHEOnDisk
# as genuinely different programs that happen to share a binary name). In
# autotools this means whichever installs second silently clobbers the first.
# CMake disallows duplicate target names, so we make the *target* name unique
# by prefixing with the leaf directory, while keeping the *output executable*
# name unchanged to match the autotools binary layout.
function(diagham_add_programs_in_directory)
    if(NOT DIAGHAM_BUILD_PROGRAMS)
        return()
    endif()

    get_filename_component(leaf ${CMAKE_CURRENT_SOURCE_DIR} NAME)

    file(GLOB program_sources RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.cc)
    foreach(src ${program_sources})
        get_filename_component(prog_name ${src} NAME_WE)

        # Skip files known to be broken upstream where patching is deferred
        # (see patches/PATCHES.md for the rationale on each excluded file).
        if(DEFINED DIAGHAM_UPSTREAM_EXCLUDED_PROGRAMS)
            list(FIND DIAGHAM_UPSTREAM_EXCLUDED_PROGRAMS "${prog_name}" excluded_idx)
            if(NOT excluded_idx EQUAL -1)
                message(STATUS "DiagHam: skipping ${prog_name} (upstream issue, see patches/PATCHES.md)")
                continue()
            endif()
        endif()

        set(target_name "${leaf}_${prog_name}")
        diagham_add_program(${target_name} ${src})
        set_target_properties(${target_name} PROPERTIES OUTPUT_NAME ${prog_name})
    endforeach()
endfunction()
