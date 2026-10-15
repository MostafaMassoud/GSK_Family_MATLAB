# GSK

MATLAB implementation of baseline GSK: `gsk_optimize.m`
(`result = gsk_optimize(problem, options)`, contract in
`docs/reference/matlab_interface.md`).

Reference source:

```text
historical source: gsk/gsk/GSK_Enhanced.m                 (primary)
historical source: atmalsgsk/atmalsgsk/cec2017/GSK.m      (cross-check, original form)
historical source: atmalsgsk/atmalsgsk/cec2017/Gained_Shared_Junior_R1R2R3.m
historical source: atmalsgsk/atmalsgsk/cec2017/Gained_Shared_Senior_R1R2R3.m
```

## Parameters (reference defaults, overridable via `options`)

`np` = 100, `kf` = 0.5, `kr` = 0.9, `k` = 10, `p` = 0.1 (senior rank
partition; `GSK_Enhanced.m` inlines `round(NP*0.1)` / `round(NP*0.9)`).

## Reference behaviors preserved

- **G_Max derivation**: `G_Max = fix(max_nfes / np)`, computed from the
  full budget (initialization evaluations included). The junior schedule
  `D_junior = ceil(D * (1 - g/G_Max).^K)` is driven by the generation
  counter `g`; because initialization consumes one population worth of
  evaluations, `g` never exceeds `G_Max` (the base never goes negative).
- **Per-generation random draw order**: junior donor R3 draws, senior
  donor draws (R1, R2, R3), junior probability mask `rand(NP,D)`, junior
  KR mask `rand(NP,D)`, senior KR mask `rand(NP,D)`. The senior mask is
  the complement of the junior probability mask before KR filtering.
- **Budget crossing**: the reference always evaluates the full generation
  (one `problem.evaluate` call for all NP children) even when fewer than
  NP evaluations remain; only the first `max_nfes - nfes` children update
  the counter and the best-so-far (sequential strict-`<` scan), while the
  greedy selection still uses every child. `result.nfes` is therefore
  clipped at `max_nfes` exactly as in `GSK_Enhanced.m` (the original
  `GSK.m` loop counter transiently reads `max_nfes + 1`, with the same
  set of counted best-so-far updates).
- **Target-error semantics**: the reference never stops early; after the
  budget is exhausted it computes `bsf_error_val = bsf_fit_var - optimum`
  and zeroes it when **strictly below** `val_2_reach` (1e-8). Port:
  `result.termination` is always `'max_evaluations'`; `result.error` gets
  the same strict-`<` zeroing when `problem.target_error` is set. When
  `problem.target_error` is NaN the zeroing is skipped; when
  `problem.optimum` is NaN, `result.error` is NaN (interface guards).
- Midpoint bound repair, pairwise greedy selection with ties keeping the
  parent (`min([fitness, children_fitness], [], 2)`), junior/senior
  better-worse displacement branching: transcribed unchanged.

## Deviations (documented, none algorithmic)

- Seeding policy: `gsk_set_rng(options)` once at entry. The default generator
  is `twister`; `options.rand_generator` may select `threefry`, `twister`,
  legacy `seed`, or legacy `state`. Wall-clock seeding is not supported.
  Runner-level seed formulas are documented in `docs/reference/seed_policy.md`.
- `best_x` is also captured during the initial population scan; the
  reference only records `bsf_solution` inside the generation loop (its
  final error value is unaffected since `bsf_fit_var` is tracked the same
  way).
- Convergence is recorded once per generation (plus one row for the
  initialized population), per `docs/reference/matlab_interface.md`; the reference
  records per evaluation.
- Dead reference code not ported: `D_Gained_Shared_Senior = D - D_junior`
  (only used by a commented-out print) and the unused `valBest` sort
  output.
