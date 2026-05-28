# Upstream patches applied by this PoC

This directory contains patches applied to the upstream DiagHam source at
configure time by `cmake/ApplyUpstreamPatches.cmake`. They surfaced during the
CMake migration: each one is a compilation error that the autotools build
either skips or buries in noise.

The patches are presented in dependency order (patches affecting more files
come first). Every patch was derived by:

1. Reading the broken file and identifying the failing API surface.
2. Grepping the codebase for the canonical pattern used by working sibling
   files solving the same physics problem.
3. Applying the surgical change needed to restore that pattern.
4. Auditing the result against the working twin's output convention
   (variable names, file-format columns, sprintf format strings).

No physics-domain assumptions were made. Every change preserves the
algorithm; only the API surface is restored.

## Class A: missing `#ifdef __LAPACK__` gating (5 patches)

DiagHam declares `LapackDiagonalize` only inside `#ifdef __LAPACK__` blocks
in `Matrix/RealSymmetricMatrix.h` and `Matrix/HermitianMatrix.h`. The
canonical DiagHam pattern (used by e.g.
`FQHESphereBosonEntanglementEntropyParticlePartition.cc`) wraps each
`LapackDiagonalize` call in:

```cpp
#ifdef __LAPACK__
    M.LapackDiagonalize(D);
#else
    M.Diagonalize(D);
#endif
```

These five files were written without the gating. Configured without LAPACK
(the PoC default), they fail to compile. The patches add the canonical
gating.

### 01-FQHECylinderDensity.patch
Density-of-states computation on the cylinder geometry. 2 LapackDiagonalize
sites (lines 278-279), both on `RealSymmetricMatrix`. Wrapped in a single
`#ifdef __LAPACK__` block.

### 02-FQHECylinderWithSU2SpinDensity.patch
Same as above with up/down spin separation. 4 sites at lines 436-439, all
on `RealSymmetricMatrix`. Wrapped in a single block.

### 03-FQHESphereQuasiholesWithSpinTimeReversalSymmetryDensity.patch
Quasi-hole density on the sphere with spin and time-reversal symmetry. 23
sites in 6 logical clusters. Each cluster wrapped in its own
`#ifdef __LAPACK__` block. Mix of `RealSymmetricMatrix` and `HermitianMatrix`.

### 04-FCIHofstadterModelCompositeFermions.patch
Composite-fermion construction on the Hofstadter (square lattice in magnetic
field) FCI. The file has 3 `LapackDiagonalize` mentions; **two are inside
`/* ... */` comment blocks** (lines 204 and 230). Only the live call at
line 251 needs wrapping.

### 05-HubbardSquareLatticeModelJ2S2.patch
Hubbard model on a square lattice with J2 (next-nearest-neighbour) hopping
and S^2 diagonalization. 2 live sites at lines 302 and 386, each on
`RealSymmetricMatrix`. Each wrapped individually.

## Class C: stale reference to a never-existed header (1 patch)

### 06-FCIDiceLatticeModel.patch

**Note:** patch 06 fixes one surface issue (the stale header reference)
but is not sufficient on its own; the Dice program needs the tight-binding
constructor arguments supplied as well. That deeper fix is patch 11
(Class G below), which completes the work patch 06 begins. Patch 06 is
retained as a separate, self-contained upstream fix so it travels cleanly
to the maintainer; with patch 11 also applied, FCIDiceLatticeModel.cc
builds, links, and runs.

Fractional Chern Insulator on the Dice lattice. Line 10 includes
`HilbertSpace/BosonOnSquareLatticeWithSpinMomentumSpaceNew.h`, a header that
**does not exist anywhere in the canonical DiagHam tree** (`find ... -name
"*MomentumSpaceNew*"` returns nothing). Line 465 calls
`new BosonOnSquareLatticeWithSpinMomentumSpaceNew(...)`.

The smoking gun is line 464, immediately above:

```cpp
// Space = new BosonOnSquareLatticeWithSpinMomentumSpace (NbrParticles, ...);
   Space = new BosonOnSquareLatticeWithSpinMomentumSpaceNew (NbrParticles, ...);
```

The file's author commented out the working call to the non-`New` variant
to try a `New` experiment that was never landed in canonical DiagHam. Line
19 also added `#include "HilbertSpace/BosonOnSquareLatticeWithSpinMomentumSpace.h" //added this`,
showing the substitution was started but not finished.

The non-`New` class exists at
`FQHE/src/HilbertSpace/BosonOnSquareLatticeWithSpinMomentumSpace.h` with
constructor `(int nbrBosons, int nbrSiteX, int nbrSiteY, int kxMomentum,
int kyMomentum, unsigned long memory = 10000000)`, exactly matching the
5-arg call site.

The patch removes the broken `#include` and swaps the active line for the
commented-out original.

DiagHam convention (verified by web search on canonical DiagHam SVN): when
classes are rewritten, the OLD version gets the `Old` suffix and the NEW
version takes the canonical name. The `New` suffix marks experimental WIP.

## Class D: copy-paste error from a sibling file (1 patch)

### 07-FQHESphereFermionsWithSpinEntanglementEntropyParticlePartition.patch
Particle-partition entanglement entropy/spectrum for fermions with spin on
a sphere. The file references an undeclared variable `SubsystemSize` at
six sites. Audit shows:

- The variable was meaningful in the **orbital-partition** version
  (`FQHESphereWithSU2SpinEntanglementEntropy.cc` declares
  `int SubsystemSize = Manager.GetInteger("min-la")` and has an outer loop
  over orbital cut size), with output format `# l_a N Lz Sz lambda`.
- The broken file is the **particle-partition** version. Particle partition
  has no `l_a` concept; the outer loop runs over particle number only.
- Working particle-partition siblings (e.g.
  `FQHESphereFermionEntanglementEntropyParticlePartition.cc`,
  `FQHESphereWithSU2SpinEntanglementEntropyParticlePartition.cc`) write
  `# N Lz lambda` or `# N Lz Sz lambda`, no `l_a` column.
- The broken file's references appear in `cout` (1 site), `sprintf` building
  `WriteVector` filenames (3 sites with `_la_%d` in the format string), and
  `DensityMatrixFile << ` data row writes (2 sites with `SubsystemSize`
  as first column).

The patch removes `SubsystemSize` from all six sites, dropping the `la_%d`
field from the filename templates and the `SubsystemSize <<` prefix from
the data-file rows. The result matches the output convention used by all
sibling particle-partition files in the same directory: consumers reading
the output now see the expected `N`-first column ordering.

## Class E: numerical precision in observable output (2 patches)

DiagHam computes results internally at IEEE-754 double precision
(approximately 17 significant decimal digits) but many result-output
sites hard-code `File.precision(14)`, `cout.precision(14)`, or
similar before streaming computed values. In C++ default ostream mode,
`precision(N)` means "at most N significant digits, with trailing
zeros trimmed", so the output is silently truncated and loses up to
6 digits of real computation. For example, an eigenvalue computed
internally as `10.472135954999576...` is written to disk as
`10.472135955` (11 sig figs); the 4 missing digits are lost.

The fix is applied only where a program emits a computed numerical
result: file streams that write `.dat` / `.vec` output (`File`,
`DensityMatrixFile`, `FileEnergy`, `OverlapRecordFile`, `FileEntropy`,
and similar), and `cout` in programs that print a result value
(energies, overlaps, charges, entropies) to standard output. Console
precision is deliberately NOT raised in programs whose `cout` carries
only usage hints and error messages ("see man page", "an interaction
file has to be provided"); raising precision there would change
nothing and would needlessly widen the patch.

This silently breaks high-precision cross-checking against
independent ED implementations, and prevents any downstream tool from
recovering the actual computed value. It also blocks any future change
to higher-precision types (e.g. `long double`, GMP, MPFR) since the
output channel would still cap at 14 digits.

The fix is mechanical and follows one pattern throughout the codebase:

1. Each affected file gets `#include <limits>` inserted after its first
   system include directive.
2. Each `XYZ.precision(N)` call with literal `N<17` at a result-output
   site is replaced by
   `XYZ.precision(std::numeric_limits<double>::max_digits10)`. On any
   IEEE-754 platform this evaluates to 17, the C++ standard guarantee
   for lossless round-trip of binary64 values through a decimal
   representation.

The pattern is forward-compatible: any subsequent change to a wider
numeric type (e.g. extended precision via `long double` or arbitrary-
precision libraries) automatically increases output precision to
match, because `std::numeric_limits<T>::max_digits10` tracks the type.

### 08-IEEE754PrecisionForEigenvalueOutput.patch

The bulk precision sweep, scoped to result-output sites. 447 files
modified across the codebase, 860 precision-site replacements (440 to
file streams, 420 to `cout` in programs that print results).

An earlier draft of this patch touched 529 files; 82 were dropped after
review because their only change was raising `cout` precision in
programs whose console output is purely diagnostic (usage text, error
messages). Those programs write their actual results to files via the
shared `MainTask` and Vector/Matrix routines, which are patched here, so
no result precision is lost by leaving their console precision alone.

Affected directories (file count):

- `src/MainTask/`               4 files   (eigenvalue writers, generic geometries)
- `FQHE/src/MainTask/`          5 files   (geometry-specific eigenvalue writers)
- `src/Vector/`                 4 files   (vector .dat writers)
- `src/Matrix/`                 1 file    (matrix .dat writer)
- `src/Programs/`              15 files   (utility programs that print results)
- `FQHE/src/Programs/`        ~255 files  (entropy, density, correlation, overlap, etc.)
- `FQHE/src/Tools/`            ~9 files   (Monte Carlo energies, spectra, MPS)
- `FTI/src/Programs/`          ~54 files  (Hubbard, FCI, FTI result writers)
- `Spin/src/Programs/`         ~65 files  (spin chain entropies and observables)
- `QuantumDots/src/`           ~27 files  (spectra and analysis result output)

Sites deliberately left unchanged:

- `%.6f`-style `sprintf` sites that format doubles into filename tokens
  (`_ratio_0.500000.dat`, `u_4.000000`). These are aesthetic filename
  components, not data values, and are intentionally left at their
  original width.
- `cout.precision` in programs whose console output is purely
  diagnostic (usage hints, error messages). These programs write their
  numerical results to files through the shared `MainTask` and
  Vector/Matrix routines, which are patched, so no result precision is
  affected.

### 09-FCIHofstadterCorrelationPrecision.patch

A small (28-line) companion patch for one file with DOS line endings
(`FCIHofstadterCorrelation.cc`). The bulk patch 08 was generated using
LF line endings throughout; this file has CRLF and produces a brittle
diff if folded into the same patch. Separated for cleanliness.

Same change pattern as patch 08: adds `#include <limits>` and replaces
the file's 2 active `precision(14)` calls (one `cout.`, one `File.`)
with `precision(std::numeric_limits<double>::max_digits10)`.

### Effect on output

| eigenvalue | before patch | after patch |
|---|---|---|
| `-4√2` ground state | `-5.6568542494924` (14 digits, trimmed) | `-5.6568542494923806` (17 digits) |
| `10 - 2/√5` | `10.472135955` (11 digits after trim) | `10.472135954999576` (17 digits) |
| `-4` band-filled level | `-4` | `-3.9999999999999947` (reveals true round-off) |
| `8` band-filled level | `8` | `7.9999999999999982` (reveals true round-off) |

The "before" output for exact integer-valued eigenvalues like `-4` and
`8` hid the floating-point round-off behind the precision-(14) display
truncation. The new output exposes the true numerical reality: those
"integer" eigenvalues are computed with the expected sub-double-epsilon
deviations from exact integer values, deviations which are present
in every QR-algorithm implementation but invisible at 14-digit precision.

Cross-check against independent Python ED for the 2×2 Hubbard model at
`U=4`:

- Before patch: max |Python ED − DiagHam| across 36 eigenvalues = 4.23 × 10⁻¹³
  (dominated by display truncation at the top of the spectrum)
- After patch: max |Python ED − DiagHam| = 4.09 × 10⁻¹⁴
  (now reflects only genuine numerical disagreement, ~10× tighter)

## Class F: enable Wannier construction for fractional Chern insulators (1 patch)

The file `FTI/src/Programs/FCI/FCIWannierConstruction.cc` (program
`FQHETopInsulatorWannierConstruction`) is research-grade Wannier-state
construction for fractional Chern insulators, used to map FCI lattice
states to fractional quantum Hall continuum states. The program needs
direct access to the underlying Fock-state representation in two
Hilbert-space classes (`FermionOnSphere`, `FermionOnTorusWithMagneticTranslations`)
to construct gauge-fixed Wannier functions. Those classes hold the
relevant data as protected members but never expose them as public
getters, so the program fails to compile.

### 10-FCIWannierConstructionEnablement.patch

Adds the missing public getter methods. Each getter is a one-line
inline function returning an existing protected member; no behaviour
change, just access.

In `FQHE/src/HilbertSpace/FermionOnSphere.h`:
- `GetStateDescription(int index)` returns `StateDescription[index]`
  (the Fock-state bit pattern for the given state index)

In `FQHE/src/HilbertSpace/FermionOnTorusWithMagneticTranslations.h`:
- `GetStateDescription(int orbit)` returns the canonical-representative
  Fock state for a magnetic-translation orbit
- `GetReorderingSign(int orbit)` returns the bit-packed sign data from
  the magnetic-translation canonicalisation
- `GetNbrStateInOrbit(int orbit)` returns the orbit size (1..MaxMomentum)

All four getters mirror the existing public-getter pattern in those
classes (e.g. `GetMaxXMomentum`, `GetNbrParticles`). The Wannier program
then compiles and links cleanly.

The program itself contains author-acknowledged scope limitations
(an explicit `// FIXME: This code has only been checked for the
Laughlin state, which always have Kpx = Kpy, and they are always
inversion symmetric`), which are research-domain caveats that the
patch does not alter. Runtime sanity checks `"reality condition broken"`
and `"Inversion broken!"` remain in place to flag cases outside the
validated regime. With the `--bold` flag the program proceeds past
the inversion check, allowing exploration of non-inversion-symmetric
states.

The patch is functionally minimal but conceptually significant: it
moves a research tool from "deferred" (i.e., unreachable) to "available
to anyone who builds DiagHam". The underlying Wannier construction
itself is unchanged.

## Class G: enable the Dice lattice FCI program (1 patch + build-system recovery)

`FTI/src/Programs/FCI/FCIDiceLatticeModel.cc` (Möller, 2019) studies
fractional Chern insulators on the Dice (T3) lattice, whose flat bands
carry Chern number |C| = 2 - a higher-Chern-number FCI laboratory. The
file was committed as work-in-progress: it carries the author's own
`//TODO: fix input parameters` markers at four constructor call sites and
a `// IS IT CORRECT?` note on the interaction-parameter mapping. It had
never compiled or linked.

Resolving it required three distinct, independently-verified fixes.

### 11-FCIDiceLatticeModelEnablement.patch

**(a) Tight-binding parameter wiring.** The three
`TightBindingModelDiceLattice` call sites passed only `tp` and `mu-six`,
but the constructor needs the full hopping set `(t1, t2, lambda1, lambda2,
mus, ...)`. The fix declares four CLI options (`t1, t2, l1, l2`) and
passes them in the documented order. The default values (t1=1.0,
t2=-0.3, l1=0.28, l2=0.2) are the canonical topological-flat-band working
point, taken verbatim from the working sibling program
`FCIKagomeLatticeModel.cc` (Kagome and Dice share the same constructor
convention). This is the answer to the author's `// IS IT CORRECT?`
question: it comes from the codebase's own working siblings, not invented.
`tp` is retained as a CLI option since it is still used in the output
filename string.

**(b) Hilbert-space class supersession.** The bosonic branch instantiated
`BosonOnSquareLatticeWithSpinMomentumSpace`, whose `GenerateStates` body
is an unimplemented stub (87 of 95 lines commented out, leaving an
infinite-recursion shell) - an abandoned 2011 draft. Git history shows
Regnault wrote that draft (commits 2011-11-08 / 2012-01-13), then two
weeks later (2012-01-27, *"add an alternate version of BosonOnSphereWithSpin
that uses similar conventions than BosonOnSphereWithSUXSpin"*) wrote the
completed replacement, `BosonOnSquareLatticeWithSU2SpinMomentumSpace`
(1114 lines, fully-implemented occupation-basis enumeration, in the build,
used by every other FCI lattice program). The patch routes the Dice
program to the completed class. Its 5-argument constructor
`(nbrBosons, nbrSiteX, nbrSiteY, kx, ky)` is identical, and it derives
from `ParticleOnSphereWithSpin` so the existing cast holds. The enumeration
is the standard published admissible-partitions / momentum-mapping
construction for two-component bosonic FCIs (e.g. Phys. Rev. X 1, 021014;
the |C|=2 two-component bosonic FCI studied in arXiv:1810.03458 is exactly
the Dice physics). The patch also removes a call to `TestFindAllStates`,
a method that exists nowhere in the codebase.

**(c) Build-system orphan recovery** (in `scripts_cmake/extract_autotools.py`,
not a source patch). Three classes the program depends on
- `TightBindingModelDiceLattice`,
`ParticleOnLatticeDiceLatticeSingleBandHamiltonian`,
`ParticleOnLatticeDiceLatticeTwoBandHamiltonian` - exist as complete,
compiling `.cc`/`.h` pairs but were never listed in any `Makefile.am`, so
neither autotools nor the generated CMake ever compiled them into their
libraries (which is why the program could never link). The
`extract_autotools.py` generator now performs *allowlisted* orphan
recovery: a `.cc` with a matching `.h`, in a single-library directory, on
an explicit allowlist, is folded into that library. The allowlist is
deliberate: a blanket "recover any orphan with a header" rule wrongly
pulls in files that are orphaned *because* they are broken (e.g.
`TightBindingModelKapitMueller.cc`, which references a removed
HofstadterSquare API). The generator also de-duplicates sources, since
upstream `Makefile.am` double-lists `TightBindingModelOFLSquareLattice.cc`.

**Verification.** On a fresh clone with patches 01-11 applied by CMake and
CMakeLists regenerated, the program compiles, links, and runs. The
single-particle path reports a flat band (flattening ~0.019, gap 2.36).
The bosonic many-body path - which exercises the previously-stubbed
enumeration - runs to completion, enumerating finite Hilbert-space
dimensions per momentum sector and producing a full momentum-resolved
spectrum with no recursion or crash. The clean-room binary is bit-identical
(SHA256 4441516506...) to the working-tree build.

## Excluded from build (1 file: see `cmake/ApplyUpstreamPatches.cmake`)

For per-file authorship/date data, inline markers, and other
grep-verified facts, see **`../DEFERRED.md`**.

### QHEFermionsTorusWithSpin (excluded)
`FQHE/src/Programs/FQHEOnTorus/QHEFermionsTorusWithSpin.cc`

Legacy duplicate of `FQHETorusFermionsWithSpin.cc`. Uses obsolete classes
(`FermionOnTorusWithSpin` whose inheritance chain doesn't reach
`ParticleOnTorusWithSpin`), obsolete API patterns
(`ArchitectureMaster` instead of `Architecture`), and has a C++ syntax
error on line 1 (stray semicolon after an `#include`). The canonical
replacement `FQHETorusFermionsWithSpin.cc` computes the same physical
quantity using the modern `FermionOnTorusWithSpinNew` class and builds
cleanly. Patching the broken file would amount to rewriting it as the
replacement that already exists. Left excluded by choice, not by defect
in this migration.

## Build outcome

Before this patch series: 464 of 474 programs build.

After patches 01-11 + `HAVE_FTI` config fix + 1 exclusion:
- **473 programs build cleanly** (gained from 464; patches 10 and 11
  enabled FCIWannierConstruction and FCIDiceLatticeModel respectively)
- 1 file explicitly skipped at configure time (QHEFermionsTorusWithSpin,
  a legacy duplicate with a canonical replacement already in the tree)
- 0 silent failures

The `HAVE_FTI` / `HAVE_FQHE` fix in `cmake/config_ac.h.in` is not part of
this patch series because it isn't a patch to upstream source, it's a
CMake-side fix that exposes constructors which the autotools build also
exposes via `--enable-fti`. It's documented here for completeness.
