# Deferred upstream files

Files excluded from the build by `cmake/ApplyUpstreamPatches.cmake` because
they cannot be patched without input that doesn't currently exist in the
canonical DiagHam tree or in this snapshot's history.

## How this file was written

Every piece of information below is from one of:

1. Direct `grep` of the file's text (TODO/FIXME markers, included headers,
   constructor calls, declared options).
2. `git log` against the DiagHam SVN-to-git snapshot at
   <https://github.com/guysoft/DiagHam>.
3. Banner comments in **canonical** DiagHam class header files
   (`.h` files) that the deferred `.cc` files depend on.

What is **not** here:
- No authorship inferred from coding style.
- No dates inferred from API conventions or "looks like an old function".
- No physics intent inferred, only what's explicitly named in the
  option strings or `cout` output strings.

The git snapshot used (`guysoft/DiagHam`) has a single commit
(`ed78a30`, 2020-10-23, author `moller`), an SVN-to-git import
sweep, so commit-level authorship history for the deferred `.cc` files
themselves is **not available from this snapshot**. The canonical DiagHam
SVN at <https://nick-ux.org/diagham/websvn> has revision-level history
that could resolve this; it was not consulted for the entries below.

## Snapshot of the git history available

```
$ git log --oneline
ed78a30 Gunnar: fixed factor of 2 in argument to exponential and
        Laguerre polynomials in definition of pseudopotentials for
        perturbed Coulomb Hamiltonian - raising doubts about accuracy
        of original CoulombHamiltonian also
        (author: moller, date: 2020-10-23)
```

This is the only commit. All deferred files appear in this commit; no
earlier history is available locally.

---

## Deferred file 1: QHEFermionsTorusWithSpin

**Path:** `FQHE/src/Programs/FQHEOnTorus/QHEFermionsTorusWithSpin.cc`

**File size:** 13,239 bytes, 323 lines

**Authorship/date (from grep):**
- No banner comment in the `.cc` file. Source contains no `Copyright`,
  `Author:`, or `last modification :` lines.
- Last-touched in the available snapshot: 2020-10-23 by `moller`
  (SVN-to-git import sweep, not a targeted change).
- `FermionOnTorusWithSpin.h` (the deprecated class this file uses) has
  banner: `Copyright (C) 2001-2002 Nicolas Regnault`,
  `last modification : 10/09/2002`.

**What it claims to compute** (from the option strings it declares):
- `-p nbr-particles`: number of fermions on a torus
- `-l max-momentum`: maximum momentum per particle
- `-s total-spin`: total Sz constraint
- `-x x-momentum`: constraint on total momentum in x direction
- `-r ratio`: aspect ratio of the torus
- `-d layerSeparation`: layer separation parameter (suggests bilayer or
  finite-thickness FQHE Coulomb interaction)

In plain terms: Coulomb interaction for spin-1/2 fermions on a torus,
diagonalised in the Lanczos basis at varying total momentum.

**Why it doesn't build (from compiler output + grep):**
- Line 1: `#include "Options/Options.h";`, stray trailing semicolon
  after `#include` directive. **Valid C++ requires no semicolon here.**
  Any compiler will reject this; the file has never compiled.
- Line 94: `FermionOnTorusWithSpin Space (NbrFermions, MaxMomentum)`, calling
  a 2-argument constructor that does not exist on the class.
  The class's constructors require 3 or 4 ints.
- Line 117: `ParticleOnTorusCoulombWithSpinHamiltonian Hamiltonian(TmpSpace, ...)`,
  passing `FermionOnTorusWithSpin*` where the constructor wants
  `ParticleOnTorusWithSpin*`. **`FermionOnTorusWithSpin` does not inherit
  from `ParticleOnTorusWithSpin`**, it inherits from
  `FermionOnSphereWithSpin`. Verified by grep on line 1 of the
  `.h` file: `class FermionOnTorusWithSpin :  public FermionOnSphereWithSpin`.

**Missing inputs/outputs/dependencies/physics:**
- None missing on input side, all required CLI options are declared.
- Dependency `FermionOnTorusWithSpin` is structurally orphaned:
  its inheritance doesn't reach `ParticleOnTorusWithSpin` and therefore
  it can't be used with any torus Hamiltonian.

**Canonical replacement exists:** `FQHETorusFermionsWithSpin.cc` (in the
same directory). Computes the same physical quantity, uses
`FermionOnTorusWithSpinNew` (canonical, inherits from
`ParticleOnTorusWithSpin`), builds cleanly. Its `.h` says
`last modification : 26/11/2007`, so the modern class was introduced
in 2007, after the broken file's 2002 vintage.

**Decision:** Patching this file would be re-creating the canonical
replacement that already exists. **Excluded permanently.** This file
is effectively dead code.

**Caveat discovered during verification (see `BUG_torus_su2_coulomb.md`):**
the canonical replacement `FQHETorusFermionsWithSpin` compiles, runs, and
produces the correct momentum structure, but its underlying spinful
Coulomb path has a separate upstream physics bug: for N >= 3 the
fully-polarized ground-state energy does not match the spinless Coulomb
result (it should, exactly). The fault is in the shared core operator
`FermionOnTorusWithSpinNew::AduAduAuAu` and is independent of this
migration. The replacement is still the right substitute for the broken
file at the build level, but the spinful torus Coulomb energies should
not be trusted quantitatively for N >= 3 until that operator is fixed
upstream. N = 2 is correct.

---

## ~~Deferred file 2: FCIWannierConstruction~~ (RESOLVED IN PATCH 10)

**Originally deferred. Now built by default thanks to patch 10.**

The file `FTI/src/Programs/FCI/FCIWannierConstruction.cc` was originally
deferred because it called four public getter methods (`GetStateDescription`,
`GetReorderingSign`, `GetNbrStateInOrbit`) on parent Hilbert-space classes
where those getters didn't exist. The corresponding member variables
were protected.

Patch 10 (`10-FCIWannierConstructionEnablement.patch`) adds the missing
public getter methods to `FermionOnSphere.h` and
`FermionOnTorusWithMagneticTranslations.h`. Each getter is an inline
one-line return of an existing protected member, mirroring the existing
public-getter pattern in those classes. No behaviour change, only access.

The program (`FQHETopInsulatorWannierConstruction`) now builds, links,
and runs. Its inline `// FIXME` markers about scope (Laughlin states
only, inversion-symmetric momenta) remain; those are research-domain
caveats that the patch does not alter. Runtime sanity checks
(`"reality condition broken"`, `"Inversion broken!"`) remain in place
to flag cases outside the validated regime.

See `patches/PATCHES.md` (Class F section) for the full audit trail.

---

## ~~Deferred file 3: FCIDiceLatticeModel~~ (RESOLVED IN PATCH 11)

**Originally deferred. Now builds, links, and runs thanks to patch 11.**

The Dice (T3) lattice hosts flat bands with Chern number |C| = 2, making
`FCIDiceLatticeModel.cc` (Möller, 2019) a higher-Chern-number FCI tool.
It was committed as work-in-progress with the author's own
`//TODO: fix input parameters` markers and a `// IS IT CORRECT?` note,
and had never compiled or linked. Three independently-verified problems
were resolved:

1. **Tight-binding parameters (the `// IS IT CORRECT?` question).** The
   `TightBindingModelDiceLattice` constructor needs `(t1, t2, lambda1,
   lambda2, mus, ...)` but the program only declared `tp` and `mu-six`.
   The answer was not a physics constant to be derived - these are free
   model parameters (hopping amplitudes a researcher chooses). The fix
   takes the canonical flat-band values directly from the working sibling
   `FCIKagomeLatticeModel.cc` (t1=1.0, t2=-0.3, l1=0.28, l2=0.2), which
   declares exactly these options with the same constructor convention.
   Answer found in the codebase, not invented.

2. **An abandoned stub Hilbert-space class.** The bosonic branch used
   `BosonOnSquareLatticeWithSpinMomentumSpace`, whose `GenerateStates` is
   87/95 lines commented out around an infinite-recursion shell, a draft
   that was later superseded. Git history (byte-for-byte verified) shows
   the completed replacement was written two weeks later
   (`BosonOnSquareLatticeWithSU2SpinMomentumSpace`, 2012-01-27,
   *"add an alternate version ... that uses similar conventions than
   BosonOnSphereWithSUXSpin"*). That class implements the standard
   published occupation-basis / momentum-mapping enumeration for
   two-component bosonic FCIs, has the identical 5-arg constructor, and is
   used by every other FCI lattice program. The Dice program is the only
   one that was still on the dead class. Patch 11 routes it to the
   completed class and removes a bogus `TestFindAllStates` call (a method
   that exists nowhere).

3. **Three classes orphaned from the build.** `TightBindingModelDiceLattice`,
   `ParticleOnLatticeDiceLatticeSingleBandHamiltonian`, and
   `ParticleOnLatticeDiceLatticeTwoBandHamiltonian` are complete, compiling
   classes that were never listed in any `Makefile.am` - so the program
   could never link. The `extract_autotools.py` generator now recovers
   allowlisted orphans (a `.cc` with matching `.h`, single-library
   directory, on an explicit allowlist) and de-duplicates sources. The
   allowlist is deliberate: a blanket rule wrongly pulls in
   `TightBindingModelKapitMueller.cc`, which is orphaned *because* it
   references a removed HofstadterSquare API and does not compile.

Verified on a fresh clone: patches 01-11 apply with zero rejects, the
program builds (clean-room SHA256 bit-identical to the working-tree
build), the single-particle path reports a flat band, and the bosonic
many-body path runs to completion through the previously-stubbed
enumeration. See `patches/PATCHES.md` (Class G) for the full audit trail.

---

## Summary table

| File | Last touched (snapshot) | Author tags found | Status |
|---|---|---|---|
| QHEFermionsTorusWithSpin | 2020-10-23 (import sweep) | None | **Excluded.** Canonical replacement (`FQHETorusFermionsWithSpin`) exists. |
| ~~FCIWannierConstruction~~ | 2020-10-23 (import sweep) | 2× FIXME | **RESOLVED in patch 10.** Builds and runs. |
| ~~FCIDiceLatticeModel~~ | 2020-10-23 (import sweep) | 4× TODO + working notes | **RESOLVED in patch 11.** Builds, links, runs. |

## Recommended next steps

1. **For Möller (Dice lattice):** patch 11 wires the `t1`, `t2`,
   `lambda1`, `lambda2` tight-binding parameters using the values from
   the working `FCIKagomeLatticeModel.cc` sibling, so the tool now builds
   and runs. Two physics choices would benefit from your confirmation:
   whether those sibling-derived tight-binding values are the intended
   defaults for the Dice lattice, and the interaction-potential mapping
   flagged by the surviving
   `// IS IT CORRECT? u-potential = u3 v-potential=u6 w-potential =delete`
   comment, which patch 11 leaves untouched.
2. **For canonical DiagHam:** consider removing
   `QHEFermionsTorusWithSpin.cc` from the source tree, since
   `FQHETorusFermionsWithSpin.cc` supersedes it cleanly.
3. **For canonical DiagHam (physics bug):** the spinful torus Coulomb
   path gives an incorrect, rank-deficient Hamiltonian for N >= 3
   (the fully-polarized ground state should equal the spinless Coulomb
   result and does not). The fault is in the shared core operator
   `FermionOnTorusWithSpinNew::AduAduAuAu`. A standalone reproducer,
   the ruled-out non-causes, and the localisation are in
   `BUG_torus_su2_coulomb.md`. This is independent of the migration but
   was surfaced by it.
4. **For users:** `FQHETopInsulatorWannierConstruction` is now
   available out of the box (patch 10). Its inline `// FIXME` markers
   document author-acknowledged scope limits (Laughlin states,
   inversion-symmetric momenta); users targeting non-Abelian states
   should expect to engage with the runtime sanity checks
   (`"reality condition broken"`, `"Inversion broken!"`) and the
   `--bold` flag.
