# AGSK

MATLAB implementation of Adaptive GSK: `agsk_optimize.m`
(`result = agsk_optimize(problem, options)`, contract in
`docs/reference/matlab_interface.md`).

Reference source:

```text
historical source: agsk/agsk/AGSK-CODE-FINAL/Adaptive_GSK_ALI.m
historical source: agsk/agsk/AGSK-CODE-FINAL/Gained_Shared_Junior_R1R2R3.m
historical source: agsk/agsk/AGSK-CODE-FINAL/Gained_Shared_Senior_R1R2R3.m
historical source: agsk/agsk/AGSK-CODE-FINAL/boundConstraint.m
```

## Parameters

- `np_init` = 100, `min_pop_size` = 12 (interface defaults). The
  reference CEC2020 driver sets `pop_size = 40*D` for `D > 5` and 100
  otherwise; pass `options.np_init` explicitly to reproduce that rule.
- Pools (fixed, reference values): `KF_pool = [0.1 1.0 0.5 1.0]`,
  `KR_pool = [0.2 0.1 0.9 0.9]`.
- Senior rank partition: the reference local senior helper hard-codes
  0.05/0.95 (`round(NP*0.05)` / `round(NP*0.95)`), passed here as
  `P = 0.05` to the shared helper.

## Reference behaviors preserved

- **Per-individual K sampling (once, at initialization)**:
  `Kind = rand(NP,1)`; `K = rand` (uniform (0,1)) where `Kind < 0.5`,
  else `K = ceil(20*rand)` (uniform integer 1..20); exact draw order
  (Kind draw, then the two conditional blocks). K is trimmed during
  population reduction, never redrawn.
- **KW probability phase**: while `nfes < 0.1*max_nfes` (checked at the
  start of each generation), `KW_ind` is reset to `[0.85 0.05 0.05 0.05]`
  every generation; afterwards
  `KW_ind = 0.95*KW_ind + 0.05*All_Imp` followed by normalization
  (`KW_ind./sum(KW_ind)`). The first adaptive generation therefore updates
  from the constant initial vector and the previous generation's
  `All_Imp`. The per-individual setting index is one `rand(NP,1)` draw
  relabeled by the reference cumulative-threshold block (transcribed
  verbatim, including its reliance on the relabeled integers exceeding
  all thresholds).
- **All_Imp improvement credit (exact computation)**:
  `dif = abs(fitness - children_fitness)` against parent fitness;
  credit per setting i is `sum(dif(child strictly better & setting == i))`;
  if any credit: normalize, floor all but the largest entry at 0.05, then
  largest entry = 1 - sum(others); otherwise uniform 1/4. Computed over
  the full generation, including children beyond the budget (reference
  behavior).
- **Junior schedule**: `D_junior = ceil(D * (1 - nfes/max_nfes).^K)` -
  **nfes ratio**, not generation ratio (this differs from baseline GSK),
  with the per-individual K vector.
- **Population reduction**: nonlinear plan
  `round((min_pop - max_pop) * (nfes/max_nfes)^(1 - nfes/max_nfes) + max_pop)`
  down to `min_pop_size = 12`, removing the worst individuals.
  Index selection uses `gsk_reduction_survivors` (provably identical to
  the reference one-at-a-time worst-removal loop, ties included); the
  per-individual arrays the reference trims (`popold`, `pop`, `fitness`,
  `K`) are trimmed locally in original row order.
- **Budget crossing**: full generation always evaluated; counter and
  best-so-far updates clipped at `max_nfes` (the reference loop counter
  transiently reads `max_nfes + 1` with the same set of counted updates);
  selection, All_Imp and the resize plan still use the full generation.
- **Target-error semantics**: checked **every generation** after the
  resize step: `bsf_error_val = bsf_fit_var - optimum`; if strictly below
  `val_2_reach` (1e-8) the error is zeroed and the run **stops**
  (`result.termination = 'target_error_reached'`, `result.error = 0`).
  On budget exit there is no end-of-run zeroing (unlike baseline GSK) -
  the reference only zeroes inside the loop check. NaN guards: the check
  is skipped when `problem.target_error` or `problem.optimum` is NaN;
  `result.error` is NaN when the optimum is NaN.

## Deviations (documented, none algorithmic)

- Seeding policy: `gsk_set_rng(options)` once at entry. Under runner
  `seed_policy='reference'`, AGSK keeps the reference `D*func*run` seed rule
  and uses the legacy `seed` generator. Direct optimizer calls default to
  `twister`, with `threefry`, `twister`, and deterministic legacy `seed`/`state`
  available for checks. Wall-clock seeding is not supported.
- `np_init` default is the interface value 100, not the reference
  dimension rule (see Parameters above).
- `best_x` is also captured during the initial population scan; the
  reference only records `bsf_solution` inside the generation loop.
- Convergence is recorded once per generation (plus one row for the
  initialized population); the reference records none with `ConvDisp=0`.
- Dead reference code not ported: `dif_val = dif(...)` (unused),
  `Imp_Ind = 1:4` in the no-improvement branch (unused),
  `D_Gained_Shared_Senior` (unused), `valBest` sort output.
