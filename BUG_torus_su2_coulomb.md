# Bug report: spinful torus Coulomb ground state is wrong for N >= 3

This is a physics correctness bug in current DiagHam, independent of the
CMake migration. It was found while verifying that the canonical program
`FQHETorusFermionsWithSpin` is a sound replacement for the broken,
excluded `QHEFermionsTorusWithSpin` (see `DEFERRED.md`).

## Summary

For two-component (SU(2)) fermions on a torus with the Coulomb
interaction, the fully spin-polarized ground state should be identical to
the spinless Coulomb ground state for the same particle number, flux, and
aspect ratio (the opposite-spin terms cannot act when every particle has
the same spin). It is identical for N = 2, but diverges for N >= 3: the
many-body Hamiltonian becomes rank-deficient (many basis states are left
completely uncoupled), and the reported ground-state energy is wrong.

## How it was found

Cross-check of two programs that should agree under full polarization:

- spinless: `FQHETorusFermionsCoulomb`
  (uses `ParticleOnTorusCoulombHamiltonian` on `FermionOnTorus`)
- spinful:  `FQHETorusFermionsWithSpin`
  (uses `ParticleOnTorusCoulombWithSpinHamiltonian` on
  `FermionOnTorusWithSpinNew`)

Run at total-spin = N (full polarization), square torus (ratio = 1),
exact diagonalization:

```
FQHETorusFermionsCoulomb   --nbr-particles N --max-momentum Nphi \
                           --ratio 1.0 --full-diag 9000
FQHETorusFermionsWithSpin  --nbr-particles N --max-momentum Nphi \
                           --total-spin N --ratio 1.0 --full-diag 9000 \
                           --redundantYMomenta
```

(`--redundantYMomenta` makes the spinful program enumerate all Ky
sectors, matching the spinless program's full-spectrum output.)

## Reproducer results

| N | Nphi | filling | spinless non-zero | SU(2) non-zero | spinless GS | SU(2) GS | agree |
|---|------|---------|-------------------|----------------|-------------|----------|-------|
| 2 | 6  | 1/3 | 15  | 15  | -0.203169 | -0.203169 | yes |
| 2 | 8  | 1/4 | 28  | 28  | -0.179442 | -0.179442 | yes |
| 2 | 12 | 1/6 | 66  | 66  | -0.159413 | -0.159413 | yes |
| 3 | 9  | 1/3 | 84  | 75  | -0.458498 | -0.410178 | no  |
| 4 | 12 | 1/3 | 495 | 152 | -0.762420 | -0.667285 | no  |

"non-zero" counts eigenvalues with |E| > 1e-10. For N = 2 the full
spectra match to ~10 digits including degeneracies (e.g. at N = 2,
Nphi = 6 both show the 3-fold Laughlin ground state and identical higher
multiplets). For N >= 3 the SU(2) Hamiltonian has many spurious
zero-energy states (9 missing at N = 3, 343 missing at N = 4), and its
ground state is too high.

The discriminating variable is the number of spectator particles, not
the filling: N = 2 is correct at filling 1/3, 1/4, and 1/6 alike, while
N = 3 and N = 4 both fail. With only one pair (N = 2) there are no
spectators and the bug does not trigger.

## What is NOT the cause (ruled out by independent checks)

- Interaction kernel: `GetVofQ` in the spinful Hamiltonian is numerically
  identical to the spinless one at the lowest Landau level (verified to
  1e-12 across many momentum transfers; at the LLL the spinless form
  factor is LaguerrePolynomial(0) = 1).
- Matrix-element coefficients: an independent reimplementation of both
  `EvaluateInteractionCoefficient` routines produces bit-identical
  coefficients (the two routines differ only in a q = 0 special case that
  evaluates to the same value, and a second-loop initialisation that does
  not change the converged sum).
- Normalisation: both use the same orbital count, summation period, and
  divisor (2 * Nphi).
- Antisymmetrisation: both build the identical four-term combination
  V(m1,m2,m3,m4) + V(m2,m1,m4,m3) - V(m1,m2,m4,m3) - V(m2,m1,m3,m4).
- Fast multiplication: disabling it (`--memory 0`) gives the identical
  wrong answer, so the bug is not in the fast-multiplication cache.

## Where the bug is

The bug is in the shared core operator path, not in the Hamiltonian's
coefficient or caching layers. The spin-polarized two-body term is
applied through

  `FermionOnTorusWithSpinNew::AduAduAuAu`
  (`FQHE/src/HilbertSpace/FermionOnTorusWithSpinNew.cc`, definition at
  line 505), which ends in a `FindStateIndex` lookup.

Many transitions that should land on a valid basis state instead return
the "not found" sentinel (`HilbertSpaceDimension`), which is why those
matrix elements vanish and the Hamiltonian becomes rank-deficient once
spectator particles are present.

A sibling operator in the same class, `AduAduAuAuV` (line 596), still
contains active debugging output (several `cout << "Sign after ..."` and
`cout << "TmpState ..."` lines, e.g. lines 619, 630, 638, 658, 678),
which indicates the SU(2) torus operators in this class were left in an
incompletely debugged state. This is circumstantial, not proof that the
fault is on a specific line; the exact defect (in `AduAduAuAu` itself or
in the `FindStateIndex` / highest-bit bookkeeping it relies on) has not
been isolated to a single statement.

## Suggested questions for the maintainer

1. Is the spinful torus Coulomb path (`ParticleOnTorusCoulombWithSpinHamiltonian`
   + `FermionOnTorusWithSpinNew`) expected to be production-ready, or is it
   known-incomplete? The leftover debug output in `AduAduAuAuV` suggests
   the latter.
2. Should `FermionOnTorusWithSpinNew::AduAduAuAu` reproduce the spinless
   result under full polarization? (Physically it must.) If so, the
   N >= 3 rank deficiency is a confirmed defect.
3. Given that the broken `QHEFermionsTorusWithSpin.cc` would have depended
   on this same family of operators, is there any spinful torus Coulomb
   result in the literature that relied on this code path and should be
   revisited?
