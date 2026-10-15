# Common MATLAB Helpers

Faithful ports of the reference behavior genuinely shared by the GSK
family. Variant-specific behavior stays inside each variant folder.

| Helper | Reference source | Notes |
|---|---|---|
| `Gained_Shared_Junior_R1R2R3.m` | identical copies next to `GSK.m` (atmalsgsk/cec2017), AGSK and APGSK `Adaptive_GSK_ALI.m`; cross-checked against the inlined O(N) form in `gsk/gsk/GSK_Enhanced.m` | junior donors: best uses 2nd/3rd best, worst uses the two just-better ranks, middles use adjacent ranks; R3 uniform with collision regeneration |
| `Gained_Shared_Senior_R1R2R3.m` | `GSK_Enhanced.m` (inlined, P = 0.1); AGSK / APGSK local copies (P = 0.05) | partition parameterized as `P`; blocks are `1..round(NP*P)`, `round(NP*P)+1..round(NP*(1-P))`, rest |
| `gsk_init_population.m` | initialization line shared verbatim by all four reference files | one `rand(NP, D)` draw |
| `gsk_initial_population_from_options.m` | runner-level fair-start wrapper around the same initialization line | uses `options.initial_population` in unified mode; otherwise draws through `gsk_init_population` |
| `gsk_restore_rng_after_initialization.m` | runner-level fair-start RNG helper | restores the post-X0 `rng` state only when an external X0 was supplied |
| `gsk_bound_repair.m` | `boundConstraint.m` (identical copies in agsk, apgsk, atmalsgsk folders); inlined in `GSK_Enhanced.m` | midpoint repair: `(parent + bound)/2`, strict `<` / `>` violation tests |
| `gsk_reduction_survivors.m` | population resizing loop in AGSK / APGSK `Adaptive_GSK_ALI.m` | returns surviving row indices in original row order |

Helper headers retain short historical source filenames for provenance; the
active implementation is the committed MATLAB code in this tree.

The two fair-start helpers are intentionally small. They let every optimizer
keep its reference initialization line while allowing `run_experiment` to own
the unified-mode `X0` and post-`X0` RNG state. That keeps the seed/fairness
policy in the runner instead of scattering conditional logic throughout the
algorithm bodies. DT-GSK uses none of the helpers in this folder: it draws
every random number from its own Threefry substreams and samples its own
`NP = 5*D` population, so the runner passes it no `X0`.

## Worked helper examples

**Initialization.** For `lb = [-5, -5]`, `ub = [5, 5]`, and one random row
`u = [0.25, 0.80]`, `gsk_init_population` applies:

```text
x = lb + u .* (ub - lb)
  = [-5, -5] + [0.25, 0.80] .* [10, 10]
  = [-2.5, 3.0]
```

The helper exists so every optimizer uses the same row-wise population convention
and the same single `rand(NP,D)` draw when the runner does not supply `X0`.

**Midpoint repair.** If a parent coordinate is `2`, a trial coordinate is `8`,
and the upper bound is `5`, midpoint repair gives:

```text
repaired = (parent + upper_bound) / 2 = (2 + 5) / 2 = 3.5
```

This is different from clipping to `5`. Midpoint repair keeps the repaired point
inside the feasible region while preserving some information about the parent.

**Fair-start restore.** In unified mode the runner draws `X0` once, saves the RNG
state immediately after that draw, and each optimizer calls
`gsk_restore_rng_after_initialization`. This means every optimizer starts from
the same population and the same next random number for a given `(D,F,run)`.

## Fidelity notes

- **Junior R3 random form.** The original helpers shared by `GSK.m`, AGSK
  and APGSK draw `R3 = floor(rand(1, NP) * NP) + 1` and regenerate
  collisions with further `rand` draws; this port keeps that form so the
  consumed random stream matches those references. `GSK_Enhanced.m` uses
  `randi(NP, 1, NP)` instead - same distribution, but a different raw
  stream for a given seed. The deterministic neighbor selection uses the
  vectorized inverse-permutation form from `GSK_Enhanced.m`, which yields
  exactly the same indices as the original `find()` loop and consumes no
  randomness.
- **Senior partition rounding.** The reference files write
  `round(NP*0.9)` / `round(NP*0.95)` literally. In IEEE doubles
  `(1 - 0.1) == 0.9` and `(1 - 0.05) == 0.95` exactly, so
  `round(NP*(1-P))` reproduces the reference block boundaries bit-for-bit
  for `P = 0.1` and `P = 0.05` at every population size (relevant because
  AGSK/APGSK shrink NP during a run). The ATMALS-GSK copy of this helper
  ends the middle block at `NP - round(NP*P)` instead, which differs only
  when `NP*P` is an exact half-integer; that variant-local behavior is
  not folded in here.
- **Reduction tie handling.** The reference removes the worst individual
  one at a time, re-sorting after each deletion. Because MATLAB `sort` is
  stable, that is exactly equivalent to dropping the last `num_remove`
  entries of one stable ascending sort (ties on the worst value are
  removed from the highest original row index downwards).
  `gsk_reduction_survivors` returns the kept indices in original row
  order, matching in-place row deletion. Callers keep all per-individual
  array bookkeeping (`popold`, `pop`, `fitness`, `K`, ...) local.
