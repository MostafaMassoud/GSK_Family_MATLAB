# APGSK

MATLAB implementation of APGSK (GSK with Adaptive Parameters):
`apgsk_optimize.m` (`result = apgsk_optimize(problem, options)`, contract
in `docs/reference/matlab_interface.md`). APGSK is a separate implementation, not a
flag on AGSK.

Reference source:

```text
historical source: apgsk/apgsk/APGSK Code/Adaptive_GSK_ALI.m
historical source: apgsk/apgsk/APGSK Code/Gained_Shared_Junior_R1R2R3.m
historical source: apgsk/apgsk/APGSK Code/Gained_Shared_Senior_R1R2R3.m
historical source: apgsk/apgsk/APGSK Code/boundConstraint.m
```

## Parameters

- Population policy: current interface default `NP = 100`; the APGSK
  reference release's CEC2020-style `NP = 200*D` for `D > 5`, else
  `NP = 250`, is opt-in via `options.np_init`. `min_pop_size` = 12.
- Pools (fixed, reference values): `KF_pool = [0.1 1.0 0.5 1.0]`,
  `kf_pool_negative = [-0.15 -0.05 -0.05 -0.15]` (named `KF_poool` (sic)
  in the reference source), `KR_pool = [0.2 0.1 0.9 0.9]`.
- Senior rank partition: 0.05/0.95 as in AGSK (`P = 0.05`).

## Reference behaviors preserved

- **KW probability phase**: identical scheme to AGSK (initial constant
  `[0.85 0.05 0.05 0.05]` while `nfes < 0.1*max_nfes`, then
  `0.95*KW_ind + 0.05*All_Imp` with normalization; same threshold
  relabeling of one `rand(NP,1)` draw).
- **KF pool-selection rule (phase 2 only)**: `KR` always comes from
  `KR_pool`; for KF the reference draws one scalar `rand` every adaptive
  generation (short-circuit `&&`, so the draw happens regardless of
  `nfes`) and uses the positive primary pool only when
  `rand >= 0.3 && nfes > 0.5*max_nfes`; otherwise the negative secondary
  pool `KF_poool`. During the initial phase KF always comes from the
  positive pool and no extra scalar is drawn.
- **Stochastic junior schedule (scalar, per generation)**: one scalar
  `rand` (drawn after the phase block); if `rand > nfes/max_nfes` the
  exponent is 0.5, else 2:
  `D_junior = ceil(1 * round(D * (1 - nfes/max_nfes)^expo))`. The result
  is a scalar; the reference expands it with `(:, ones(1, D))` against
  `rand(NP, D)` for the junior probability mask (transcribed unchanged).
- **K drawn but unused**: the reference samples the per-individual K
  exactly like AGSK at initialization and trims it during reduction, but
  its junior schedule never uses it (the AGSK formula is commented out in
  the source). The draws and the trimming are kept for random-stream
  fidelity.
- **All_Imp update, greedy selection, nonlinear population reduction,
  budget-crossing and target-error semantics**: identical to AGSK
  (see `src/optimizers/agsk/README.md`); reduction index selection via
  `gsk_reduction_survivors`, with `popold`/`pop`/`fitness`/`K` trimmed
  locally; per-generation target check zeroes the error and stops
  (`'target_error_reached'`), no end-of-run zeroing on budget exit;
  NaN guards on `problem.target_error` / `problem.optimum`.

## Deviations (documented, none algorithmic)

- Seeding policy: `gsk_set_rng(options)` once at entry. Under runner
  `seed_policy='reference'`, APGSK keeps the reference `D*func*run` seed rule
  and uses the legacy `seed` generator. Direct optimizer calls default to
  `twister`, with `threefry`, `twister`, and deterministic legacy `seed`/`state`
  available for checks. Wall-clock seeding is not supported.
- `KF_poool` renamed `kf_pool_negative` (original name cited in a
  comment).
- `best_x` is also captured during the initial population scan; the
  reference only records `bsf_solution` inside the generation loop.
- Convergence is recorded once per generation (plus one row for the
  initialized population); the reference records none with `ConvDisp=0`.
- Dead reference code not ported: `dif_val`, `Imp_Ind` in the
  no-improvement branch, `D_Gained_Shared_Senior`, `valBest`.
