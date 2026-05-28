# ============================================================================
#  DiagHam: CMake build system (modernisation proof-of-concept)
# ============================================================================
#
#  This CMakeLists.txt is a proof-of-concept replacement for DiagHam's
#  legacy autotools build.
#
#  Scope of this PoC:
#    - All static libraries under Base/src/ and src/ (the core libraries)
#    - All 34 generic executables under src/Programs/
#    - FQHE module: libraries and programs across FQHEOnSphere, FQHEOnDisk,
#      FQHEOnTorus, FQHEOnCylinder, FQHEOnLattice
#    - FTI module: libraries and Hubbard / FCI / FTI executables (FTI's
#      hamiltonians and operators are derived from FQHE's, so FTI needs
#      FQHE built and linked)
#
#  Out of scope (deferred to a real production CMake rollout):
#    - Spin and QuantumDots modules (same pattern, more code)
#    - Optional libraries: LAPACK/BLAS, GSL, GMP, MPACK, FFTW, ScaLAPACK
#    - MPI parallel build (toggled via __MPI__; needs find_package(MPI))
#    - Spack/distribution packaging metadata
#
#  Author: Paul Watford
#  Reference build: matches autotools output binary-for-binary on Linux/x86_64
# ============================================================================

cmake_minimum_required(VERSION 3.16)

project(DiagHam
    VERSION 0.01
    DESCRIPTION "Exact Diagonalization toolkit for strongly correlated systems"
    LANGUAGES CXX C
)

# ----------------------------------------------------------------------------
# Build configuration
# ----------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# ----------------------------------------------------------------------------
# Options, mirroring the autotools AC_ARG_ENABLE flags
#
# NOTE for SSI work: the autotools configure.ac has 36 such flags. A full
# production CMake migration must preserve every one of them. This PoC
# implements pthread (__SMP__), debug mode, 64-bit pointers, and the
# stub for LAPACK. Others to be added: --enable-gsl, --enable-bz2,
# --enable-gmp, --enable-mpack, --enable-fftw, --enable-scalapack, --enable-mpi.
# ----------------------------------------------------------------------------
option(DIAGHAM_BUILD_FQHE     "Build the FQHE module (sphere/disk/torus/cylinder/lattice)" ON)
option(DIAGHAM_BUILD_FTI      "Build the FTI module (Hubbard models, FCI, FTI; requires FQHE)" ON)

# FTI's hamiltonians and operators inherit from FQHE's, so FTI cannot build
# or link without FQHE. Enforce the dependency at configure time.
if(DIAGHAM_BUILD_FTI AND NOT DIAGHAM_BUILD_FQHE)
    message(FATAL_ERROR
        "DIAGHAM_BUILD_FTI requires DIAGHAM_BUILD_FQHE. "
        "FTI links against QHEHamiltonian, QHEHilbertSpace, QHEOperator, "
        "QHEArchitectureOperation, QHEMainTask, QHEFiles, QHEFunctionBasis "
        "and QHEQuantumNumber. Re-configure with -DDIAGHAM_BUILD_FQHE=ON.")
endif()
option(DIAGHAM_USE_SMP        "Enable pthread-based shared-memory parallelism" ON)
option(DIAGHAM_USE_DEBUG      "Define __DEBUG__ for runtime sanity checks" ON)
option(DIAGHAM_USE_LAPACK     "Enable LAPACK support (optional)" OFF)
option(DIAGHAM_USE_MPI        "Enable MPI support (optional)" OFF)
option(DIAGHAM_BUILD_PROGRAMS "Build executables (not just libraries)" ON)

# ----------------------------------------------------------------------------
# Compile-time macros for src/config.h, corresponds to autoconf's config_ac.h
# ----------------------------------------------------------------------------
set(DIAGHAM_COMPILE_DEFS "")

# Endianness
include(TestBigEndian)
test_big_endian(IS_BIG_ENDIAN)
if(IS_BIG_ENDIAN)
    list(APPEND DIAGHAM_COMPILE_DEFS "__BIGENDIAN__")
else()
    list(APPEND DIAGHAM_COMPILE_DEFS "__LITTLEENDIAN__")
endif()

# 64-bit pointers
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    list(APPEND DIAGHAM_COMPILE_DEFS "__64_BITS__")
endif()

# __int128 support, gcc/clang have it, MSVC does not
# Note: src/config.h *also* defines LONGLONG/ULONGLONG; defining them here
# would cause "macro redefined" warnings. We just set the flag macro.
include(CheckTypeSize)
check_type_size("__int128" SIZEOF_INT128 LANGUAGE CXX)
if(HAVE_SIZEOF_INT128)
    list(APPEND DIAGHAM_COMPILE_DEFS "__128_BIT_LONGLONG__")
endif()

# sstream style (modern C++ <sstream> rather than ancient strstream)
list(APPEND DIAGHAM_COMPILE_DEFS "__SSTREAM_STYLE__")

# Machine precision constant, matches autotools' MACHINE_PRECISION
list(APPEND DIAGHAM_COMPILE_DEFS "MACHINE_PRECISION=1e-14")

# Cluster architecture and Hilbert space "feature" macros, these come
# from src/config.h via the HAVE_CONFIG_H -> config.h -> config_ac.h chain.
# We do NOT redefine them here, because some source files (e.g.
# DelocalizedRealVector.cc) use them in an #ifdef without including
# config.h first, so they're effectively dead code in the autotools
# build, and we preserve that behaviour to match output byte-for-byte.
#
# A production migration would either:
#   (a) fix the offending files to #include "config.h" properly, then
#       enable USE_CLUSTER_ARCHITECTURE here, or
#   (b) remove the dead-code paths entirely.
# This PoC chooses neither, it just matches what autotools produces.

if(DIAGHAM_USE_DEBUG)
    list(APPEND DIAGHAM_COMPILE_DEFS "__DEBUG__")
endif()

# Pthread (DiagHam's misleadingly-named "SMP" mode is actually pthreads,
# not OpenMP, see briefing document section 2)
if(DIAGHAM_USE_SMP)
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)
    list(APPEND DIAGHAM_COMPILE_DEFS "__SMP__")
endif()

# MPI (stub)
if(DIAGHAM_USE_MPI)
    find_package(MPI REQUIRED)
    list(APPEND DIAGHAM_COMPILE_DEFS "__MPI__")
endif()

# LAPACK (stub)
if(DIAGHAM_USE_LAPACK)
    find_package(LAPACK REQUIRED)
    list(APPEND DIAGHAM_COMPILE_DEFS "__LAPACK__")
endif()

# Apply globally to every target in this project
add_compile_definitions(${DIAGHAM_COMPILE_DEFS})

# DiagHam expects HAVE_CONFIG_H so it can include "config.h"
add_compile_definitions(HAVE_CONFIG_H)

# Suppress noise from the legacy codebase: many warnings are spurious in
# 24-year-old C++98-ish code. A production migration would clean these.
add_compile_options(-Wno-deprecated -Wno-write-strings -Wno-narrowing -Wno-format)

# ----------------------------------------------------------------------------
# Include directories, every source file uses paths like
#   #include "Architecture/AbstractArchitecture.h"
# so src/ and Base/src/ must both be on the search path.
# ----------------------------------------------------------------------------
include_directories(
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/Base/src
    ${CMAKE_BINARY_DIR}/src              # for the generated config.h
)

if(DIAGHAM_BUILD_FQHE)
    # FQHE sources include their own headers via paths like
    #   #include "Architecture/ArchitectureOperation/FQHEDiskQuasiholePropagatorOperation.h"
    # so FQHE/src must be on the search path.
    include_directories(${CMAKE_SOURCE_DIR}/FQHE/src)
endif()

if(DIAGHAM_BUILD_FTI)
    # FTI sources include their own headers via paths like
    #   #include "Architecture/ArchitectureOperation/FTIComputeBandStructureOperation.h"
    # and reach into FQHE for the base classes their hamiltonians derive from.
    #
    # NOTE: this is a real fix relative to the autotools build, which sets
    # only -I src and -I Base/src on FTI compilations. That's a long-standing
    # bug: `make -C FTI/src` fails out of the box on a clean autotools setup.
    # The CMake migration is the right moment to fix this.
    include_directories(${CMAKE_SOURCE_DIR}/FTI/src)
endif()

# ----------------------------------------------------------------------------
# Generate the config.h header that DiagHam includes everywhere
#
# We surface the module-presence macros HAVE_FQHE / HAVE_FTI here, mirroring
# what autotools does on `--enable-fqhe` / `--enable-fti`. These macros gate
# FTI-aware constructor declarations in shared FQHE headers, so they must be
# defined whenever the corresponding modules are built (otherwise downstream
# FCI programs see only the copy-constructor and fail to compile).
# ----------------------------------------------------------------------------
if(DIAGHAM_BUILD_FQHE)
    set(HAVE_FQHE 1)
endif()
if(DIAGHAM_BUILD_FTI)
    set(HAVE_FTI 1)
endif()

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src)
configure_file(
    ${CMAKE_SOURCE_DIR}/cmake/config_ac.h.in
    ${CMAKE_BINARY_DIR}/src/config_ac.h
    @ONLY
)

# ----------------------------------------------------------------------------
# A helper that wraps add_library and add_executable so source files can be
# auto-discovered while preserving the autotools library granularity.
# ----------------------------------------------------------------------------
include(${CMAKE_SOURCE_DIR}/cmake/DiagHamHelpers.cmake)

# ----------------------------------------------------------------------------
# Apply upstream-bug patches and set the exclusion list. See patches/PATCHES.md
# for what each patch does and why each excluded file was excluded.
# ----------------------------------------------------------------------------
include(${CMAKE_SOURCE_DIR}/cmake/ApplyUpstreamPatches.cmake)

# ----------------------------------------------------------------------------
# Build the libraries
# ----------------------------------------------------------------------------
add_subdirectory(Base/src)
add_subdirectory(src)

if(DIAGHAM_BUILD_FQHE)
    add_subdirectory(FQHE/src)
endif()

if(DIAGHAM_BUILD_FTI)
    add_subdirectory(FTI/src)
endif()

# ----------------------------------------------------------------------------
# Summary message
# ----------------------------------------------------------------------------
message(STATUS "")
message(STATUS "DiagHam CMake configuration:")
message(STATUS "  Build type:     ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard:   ${CMAKE_CXX_STANDARD}")
message(STATUS "  SMP (pthreads): ${DIAGHAM_USE_SMP}")
message(STATUS "  LAPACK:         ${DIAGHAM_USE_LAPACK}")
message(STATUS "  MPI:            ${DIAGHAM_USE_MPI}")
message(STATUS "  FQHE module:    ${DIAGHAM_BUILD_FQHE}")
message(STATUS "  FTI module:     ${DIAGHAM_BUILD_FTI}")
message(STATUS "  Build programs: ${DIAGHAM_BUILD_PROGRAMS}")
message(STATUS "")
