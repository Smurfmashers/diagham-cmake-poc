# ============================================================================
# ApplyUpstreamPatches.cmake: apply upstream-bug patches at configure time
# ============================================================================
#
# CMake migration of DiagHam surfaced ten files in the FQHE and FTI modules
# that do not compile against the canonical DiagHam codebase. The autotools
# build hides these failures: most of the broken files are unreachable from
# the default build, and the few that are reachable produce errors that get
# lost in the noise.
#
# This module applies a numbered patch series under ${CMAKE_SOURCE_DIR}/patches
# at configure time. A sentinel file in the build tree records the patch
# fingerprint so re-runs skip work that has already been done.
#
# What each patch does is documented in patches/PATCHES.md, with explicit
# audit trails (sibling-file comparisons, header inspections, and physics
# notes) that justify every change.
#
# Files NOT patched (excluded from the build instead, see DiagHamHelpers.cmake)
# are listed in DIAGHAM_UPSTREAM_EXCLUDED_PROGRAMS and documented in PATCHES.md.
# ============================================================================

set(DIAGHAM_PATCH_DIR ${CMAKE_SOURCE_DIR}/patches)
set(DIAGHAM_PATCH_SENTINEL ${CMAKE_BINARY_DIR}/.diagham_upstream_patches_applied)

if(NOT EXISTS ${DIAGHAM_PATCH_DIR})
    message(STATUS "DiagHam: no upstream patch directory found, skipping")
    set(DIAGHAM_UPSTREAM_EXCLUDED_PROGRAMS "" CACHE INTERNAL "")
    return()
endif()

file(GLOB patch_files ${DIAGHAM_PATCH_DIR}/[0-9]*.patch)
list(SORT patch_files)

if(NOT patch_files)
    message(STATUS "DiagHam: no upstream patches to apply")
else()
    # Compute a content fingerprint of the patches so we re-apply on any change
    set(patch_fingerprint "")
    foreach(p ${patch_files})
        file(MD5 ${p} hash)
        string(APPEND patch_fingerprint "${hash}\n")
    endforeach()

    set(need_apply TRUE)
    if(EXISTS ${DIAGHAM_PATCH_SENTINEL})
        file(READ ${DIAGHAM_PATCH_SENTINEL} existing_fingerprint)
        if("${existing_fingerprint}" STREQUAL "${patch_fingerprint}")
            set(need_apply FALSE)
            message(STATUS "DiagHam: upstream patches already applied (sentinel matches)")
        endif()
    endif()

    if(need_apply)
        find_program(PATCH_EXECUTABLE patch REQUIRED)

        foreach(p ${patch_files})
            get_filename_component(pname ${p} NAME)
            execute_process(
                COMMAND ${PATCH_EXECUTABLE} -p1 --silent -i ${p}
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                RESULT_VARIABLE patch_result
                OUTPUT_VARIABLE patch_output
                ERROR_VARIABLE patch_error
            )
            if(patch_result EQUAL 0)
                message(STATUS "DiagHam: applied ${pname}")
            else()
                message(FATAL_ERROR
                    "DiagHam: failed to apply ${pname}\n"
                    "  result: ${patch_result}\n"
                    "  output: ${patch_output}\n"
                    "  error:  ${patch_error}")
            endif()
        endforeach()

        file(WRITE ${DIAGHAM_PATCH_SENTINEL} "${patch_fingerprint}")
    endif()
endif()

# Files excluded from the build because they cannot be patched without
# physics-domain decisions that belong to the maintainer. See PATCHES.md.
set(DIAGHAM_UPSTREAM_EXCLUDED_PROGRAMS
    "QHEFermionsTorusWithSpin"         # legacy duplicate of FQHETorusFermionsWithSpin (see DEFERRED.md)
    CACHE INTERNAL "Programs excluded due to upstream issues"
)
