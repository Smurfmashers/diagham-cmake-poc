# DiagHam: CMake Migration Proof-of-Concept

[DiagHam](http://www.nick-ux.org/diagham/wiki) is an exact-diagonalization
toolkit for strongly correlated quantum systems, fractional quantum Hall,
fractional Chern insulators, Hubbard models, spin chains. It is ~573,000
lines of C++ across ~2,350 classes and 565 executables, built on a 24-year-old
GNU autotools system that the upstream community has identified as a
modernisation target.

This repository holds initial work on replacing that autotools build with
a clean CMake build, following discussion with Gunnar Möller (University
of Kent). It also exercises one of DiagHam's Hubbard-model executables
end-to-end to confirm the build chain produces correct physics output.

A note on scope: most of this is assembly rather than invention. The
build fixes restore patterns already present in DiagHam's own working
files, and the physics, the algorithms, and the bulk of the engineering
remain the work of the DiagHam authors. This proof of concept collects
those pieces into a CMake build and verifies that the result is correct.

---

## What this repository contains

```
.
|---- CMakeLists.txt              top-level, ~230 lines
|---- cmake/
|   |---- DiagHamHelpers.cmake          helper macros (diagham_add_library, ...)
|   |---- ApplyUpstreamPatches.cmake    applies upstream-bug patches at configure time
|   |---- config_ac.h.in                autoconf-equivalent header template
|   +---- verify_build.sh               79-check build-equivalence verification script
|---- scripts_cmake/
|   +---- extract_autotools.py     reads upstream Makefile.am, emits CMakeLists.txt
|---- patches/
|   |---- PATCHES.md                11 upstream-bug patches, with audit trail
|   |---- 01-FQHECylinderDensity.patch
|   |---- 02-FQHECylinderWithSU2SpinDensity.patch
|   |---- 03-FQHESphereQuasiholesWithSpinTimeReversalSymmetryDensity.patch
|   |---- 04-FCIHofstadterModelCompositeFermions.patch
|   |---- 05-HubbardSquareLatticeModelJ2S2.patch
|   |---- 06-FCIDiceLatticeModel.patch
|   |---- 07-FQHESphereFermionsWithSpinEntanglementEntropyParticlePartition.patch
|   |---- 08-IEEE754PrecisionForEigenvalueOutput.patch
|   |---- 09-FCIHofstadterCorrelationPrecision.patch
|---- benchmarks/
|   |---- BENCHMARK.md             physics verification log + independent Python ED
|   |---- hubbard_ed.py            100-line independent reference implementation
|   |---- fermions_hubbard_square_x_2_y_2*.dat.txt   (saved 2x2 DiagHam output)
|   +---- fermions_hubbard_square_x_2_y_4*.dat.txt   (saved 2x4 DiagHam output)
|---- DEFERRED.md                  1 excluded file: what it does, what's missing
|---- HUBBARD_BENCHMARK.md         Hubbard ED demonstration with physics output
+---- README.md                    this file
```

When the extract script is run against an upstream DiagHam checkout it
generates a set of per-subdirectory `CMakeLists.txt` files under
`Base/src/`, `src/`, and `FTI/src/` (47 files in total: 1 top-level + 46
per-subdirectory). Those generated files live in the DiagHam tree, not
in this repository.

## What works

```
cd /path/to/DiagHam
cmake -B build .                  # patches apply at configure time
cmake --build build -j4
build/cmake/verify_build.sh
```

Current build outcome (with patches applied, default config: no LAPACK,
SMP enabled, FQHE and FTI modules enabled):

- **50 of 50 static libraries** build cleanly (Base/src + src + FQHE/src + FTI/src)
- **473 of 474 programs** build cleanly. 1 is explicitly skipped at
  configure time with documented rationale, see `DEFERRED.md`.
- The verification script's per-library symbol-count checks pass on the
  core (Base/src + src) libraries where they're meaningful.
- Hubbard 2x2 U=4 benchmark: ground state `-5.6568542494924`, matching
  the analytical answer `-4√2 = -5.6568542494923806` (matched to full IEEE-754 double precision after patch 08)
  (machine precision). See `benchmarks/BENCHMARK.md` for the full
  verification log including an independent Python ED cross-check.

If `DIAGHAM_BUILD_FQHE=OFF` and `DIAGHAM_BUILD_FTI=OFF`, the build
reduces to the original core-only scope (32 libraries + 34 programs)
that matches `verify_build.sh`'s 79 byte-level checks against the
autotools build.

## Why CMake (and what the autotools build does today)

The upstream `configure.ac` has **36 `AC_ARG_ENABLE` / `AC_ARG_WITH` flags**:
`--enable-lapack`, `--enable-gsl`, `--enable-mpi`, `--enable-bz2`,
`--enable-gmp`, `--enable-mpack`, `--enable-fftw`, `--enable-scalapack`,
`--with-blas-libs=...`, and so on. Each flag is some cluster admin's
hard-won dependency chain. Any CMake migration must preserve every one of
them, this PoC implements the three most-used (`__SMP__`, `__LAPACK__`,
`__MPI__`) and stubs out the rest, with clear comments showing where the
others slot in.

The autotools build also relies on two custom Perl scripts
(`scripts/genmake.pl` and `scripts/genam.pl`) that auto-generate
`Makefile.am` entries from directory contents. Under CMake, that whole
layer goes away: adding a new program is just dropping a `.cc` file in the
relevant Programs directory.

## Methodology

The per-subdirectory CMakeLists.txt files are auto-generated by
`scripts_cmake/extract_autotools.py`, which parses every upstream `Makefile.am`
to extract its `libFOO_a_SOURCES` lists and emits the equivalent CMake.
The Python script is itself part of the PoC, a real migration
benefits from a *reproducible* derivation of CMake from autotools, not
just a one-shot hand-port. Re-running the script after any upstream
`Makefile.am` change gives an updated CMake snapshot.

The generated files are deliberately thin (each one a few `diagham_add_library`
calls); all complexity lives in `cmake/DiagHamHelpers.cmake`.

## Upstream issues surfaced during the migration

The CMake port surfaced **thirteen** long-standing issues in the upstream
codebase that the autotools build either silently hid or fenced off
behind broken include paths. Three are pre-existing notes from the
core-only iteration of this PoC; ten emerged after FQHE and FTI were
brought into scope.

### Three from the core iteration

- **`Fermions.cc` orphan from May 2001**, still listed in
  `libQHEHilbertSpace_a_SOURCES` but its include path is missing from
  the upstream `Makefile.am`. A 24-year-old orphan in the build list.
- **`DelocalizedRealVector.cc` dormant dead code**, entirely wrapped
  in `#ifdef USE_CLUSTER_ARCHITECTURE`. The file doesn't
  `#include "config.h"`, so the macro never reaches it and the build
  produces a 1456-byte object file with no symbols.
- **`make -C FTI/src` fails out of the box**, FTI's `Makefile.am`
  only sets `-I src -I Base/src`, but FTI sources include from
  `FQHE/src` too. A clean `./configure && make -C FTI/src` fails.

### Thirteen more surfaced once FQHE + FTI came into scope, plus deeper inspection

| Class | Count | Issue | Resolution |
|---|---:|---|---|
| A | 5 | Missing `#ifdef __LAPACK__` gating around `LapackDiagonalize` | Patched (canonical pattern lift) |
| B | 3 | Stale constructor / API mismatches | 1 patched; 2 since resolved (now Classes F, G via patches 10, 11) |
| C | 1 | `#include` of a header that never existed (`*New.h`) | Patched (author left the working version commented out) |
| D | 1 | Undeclared variable `SubsystemSize` (copy-paste from sibling) | Patched (matched to working twin's convention) |
| E | 2 | `precision(14)` hardcoded at result-output sites, silently truncating output below IEEE-754 double precision | Patched in 2 parts (patches 08, 09) across 448 result-writing files; uses `std::numeric_limits<double>::max_digits10` |
| F | 1 | `FCIWannierConstruction.cc` (Wannier construction for fractional Chern insulators) references public getter methods that were never defined on parent Hilbert-space classes | Patched (patch 10); adds 4 inline getters to existing classes |
| G | 1 | `FCIDiceLatticeModel.cc` (Dice-lattice \|C\|=2 FCI) had unwired tight-binding parameters, depended on an abandoned stub Hilbert-space class, and on 3 classes orphaned from every Makefile.am | Patched (patch 11); wires t1/t2/l1/l2 from the Kagome sibling, routes to the completed SU2 boson class, recovers the 3 orphaned classes via allowlisted build-system recovery |
| - | 1 | `HAVE_FTI` macro not defined in our CMake config | Fixed in `cmake/config_ac.h.in` |

11 are patched in `patches/` with full audit trails in
[`patches/PATCHES.md`](patches/PATCHES.md). 1 is deferred to the
maintainer's review (a legacy duplicate with a canonical replacement), documented in [`DEFERRED.md`](DEFERRED.md) with
grep-verified evidence: file sizes, inline TODO/FIXME markers,
git-history snapshots, and the specific missing-input physics
parameters where applicable.

## Demonstration: Hubbard ED with machine-precision physics output

With the build working, the next check is that the produced binaries
give correct physics on problems with known answers. Two documents cover
this:

- **`HUBBARD_BENCHMARK.md`** (repo root), original U-sweep across
  `{0,1,2,3,4,5,6,7,8}` at 2x2 half-filling.
- **`benchmarks/BENCHMARK.md`**, physics verification log for this
  iteration of the PoC, including an independent **100-line Python
  exact diagonalisation** (`benchmarks/hubbard_ed.py`) that builds
  the Hubbard Hamiltonian from scratch in the 2nd-quantised Fock basis
  and reproduces DiagHam's output to machine precision on both 2x2
  (basis dim 36) and 2x4 (basis dim 4900) test cases.

Highlights:

- **2x2 Hubbard, half-filling, U=4**: DiagHam gives ground-state energy
  `-5.6568542494924`. Analytical value: `-4*sqrt(2) = -5.656854249492381...`.
  **Agreement to 1.95×10⁻¹⁴**, the limit of double-precision arithmetic.
- **2x4 Hubbard, half-filling, U=4**: DiagHam gives `E_0 = -10.252952955264`.
  Independent Python ED gives `-10.2529529552636`. Match to 4×10⁻¹³.
- **Strong-coupling U-scaling test (U ∈ {50, 100, 200, 500}):** E₀ · U
  converges to a constant (≈ −48.14) confirming the expected 1/U scaling
  in the Heisenberg limit.

## Beyond this iteration

The current PoC covers the core build chain plus the FQHE and FTI
subsets, with 11 patches for surfaced upstream issues and one file
excluded from the build (recommended for upstream removal). The following
remain out of scope:

- **Spin and QuantumDots modules.** Same pattern as FQHE/FTI, just more
  source files. The pattern is established and the migration extends
  trivially.
- **Optional features beyond pthread.** LAPACK/BLAS, MPI, GSL, GMP,
  FFTW, MPACK, ScaLAPACK each need a `find_package()` block plus
  appropriate `target_link_libraries` calls. Stubs are in the
  top-level CMakeLists.txt with comments showing the pattern.
  **Note:** turning on `DIAGHAM_USE_LAPACK=ON` currently exposes
  5000+ further compilation errors inside `src/Matrix/HermitianMatrix.h`
  (a `doublecomplex` typedef gap unrelated to our patches). LAPACK
  enablement is its own scoped task.
- **The 1 remaining deferred file.** Two of the originally-deferred
  files have since been resolved (patch 10 adds the getter methods that
  unblock `FCIWannierConstruction`; patch 11 wires the tight-binding
  parameters and recovers the orphaned classes for `FCIDiceLatticeModel`).
  The one file left deferred is `QHEFermionsTorusWithSpin`, recommended
  for upstream removal since `FQHETorusFermionsWithSpin` supersedes it.
  See `DEFERRED.md` for the full disposition.
- **Spack/Linux distribution packaging.**
- **GitHub Actions CI workflow.**
- **Doxygen documentation extraction.** Every class in DiagHam has a
  license header and method-level docstring; running Doxygen on the
  existing tree produces a real API manual with no source changes.

## Build dependencies

- CMake >= 3.16
- C++11 compiler (gcc, clang, etc.)
- pthread

Optional: LAPACK, MPI (toggle via `-DDIAGHAM_USE_LAPACK=ON`, `-DDIAGHAM_USE_MPI=ON`).

## License

DiagHam is licensed under the GNU General Public License, version 2 or
later (see `COPYING` in the upstream repository). The contributions in
this proof of concept are released under the same terms. See the
`LICENSE` file for the contribution copyright notice, a statement of what
was changed, and the full license text.

## Acknowledgements

The upstream codebase is the work of Nicolas Regnault, Gunnar Möller,
Duc Phuong Nguyen, and contributors over 24 years.
