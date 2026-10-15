# eGSK

MATLAB implementation of eGSK (Enhanced Gaining-Sharing Knowledge-based
algorithm; Jawad, Roshdy & Mohamed, https://doi.org/10.1016/j.rico.2025.100542):
GSK with separate junior/senior knowledge factors, late-stage membership-based
factor adaptation, a population-level selection rule, and an fmincon-based
local refinement (IP).

Entry point: `egsk_optimize.m` (`result = egsk_optimize(problem, options)`,
contract in `docs/reference/matlab_interface.md`).

## Historical Source Notes

```text
historical source: egsk/egsk/finaleGSK2023/eGSK.m
historical source: egsk/egsk/finaleGSK2023/IP.m
historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Junior_R1R2R3.m
historical source: egsk/egsk/finaleGSK2023/Gained_Shared_Senior_R1R2R3.m
historical source: egsk/egsk/finaleGSK2023/boundConstraint.m
```

## Files

- `egsk_optimize.m` -- `eGSK.m` transcribed line by line; local subfunction
  `boundConstraint` (midpoint repair, byte-identical reference copy).
- `egsk_gained_shared_senior.m` -- the eGSK-local senior helper. Kept local
  because it DIFFERS from `src/common/Gained_Shared_Senior_R1R2R3.m`: no `P`
  argument, fixed `round(NP*0.1)` / `round(NP*0.9)` partition boundaries
  (byte-identical to the ATMALS-GSK cec2011 senior copy).
- `egsk_ip_refine.m` -- faithful port of `IP.m` (see below).

The junior helper copy in the reference folder differs from the shared one
only by a cosmetic comma (`if i > 1000,` vs `if i > 1000`) -- behaviorally
and RNG-stream identical -- so the shared
`src/common/Gained_Shared_Junior_R1R2R3.m` is called directly.

## Transcribed behaviors (preserved exactly)

1. **Parameters**: `KF1 = KF2 = 0.5*ones(NP,1)` separate junior/senior
   factors, `KR = 1`, `K = 10` (scalar, so `D_Gained_Shared_Junior =
   ceil(D*(1-g/G_Max)^K)` is a scalar broadcast). `np = 100`,
   `G_Max = fix(max_nfes/np)`.
2. **Late-stage factor adaptation** (every generation with
   `g >= 0.75*G_Max`, i.e. the last ~25% of the generation budget): KF1 per
   individual from a triangular membership over
   `(a1,b1,c1) = (fitness(Rg1), fitness(Rg3), fitness(Rg2))`; KF2 from the
   scalar anchors `fitness(min(R1)) / fitness(min(R2)) / fitness(min(R3))` --
   `min` over the INDEX vectors, a reference quirk. Both are then forced to
   zero outside (0,1): `KF(KF>=1)=0; KF(KF<=0)=0` AS WRITTEN (boundary
   values inclusive). The whole-vector re-assignment inside the
   per-individual loop is also kept as written.
3. **Population-level selection twist**: if `sum(fitness) <
   sum(children_fitness)` the parent population is the base and improving
   children are copied in; otherwise the children become the base and
   strictly-better parents are restored. Both branches keep the pairwise
   best; ties go to the base population (parents in the first branch,
   children in the second). NOT replaced by plain pairwise selection.
4. **Escape + IP refinement**: in the same late stage, when the best-so-far
   is still above target (`bsf > optimum + val_2_reach`) and
   `std([a2 b2 c2])*1e-2 <= 1`, `IP` runs fmincon and the refined point
   replaces the incumbent at row `NO_i` (the row index that produced the
   current best-so-far -- possibly stale, as written), overwriting
   `fitness(NO_i)`.
5. **IP port** (`egsk_ip_refine.m`): budget `IP_FE = ceil(0.002*max_nfes)`;
   exact reference options `optimset('Display','off','algorithm','sqp',
   'UseParallel','never','MaxFunEvals',IP_FE)` (verified to work with
   fmincon on R2025b); `x0 = bestx'` (column); improvement test
   `(f - FUN) > 0`; `nfes = nfes + details.funcCount` (so `result.nfes` can
   exceed `max_nfes` slightly, exactly like the reference counter). The
   reference objective `fmincon(@cec17_func, ..., I_fno)` is adapted to
   `@(z) problem.evaluate(z(:).')`; the pass-through `g`/`run_funcvals`
   arguments of `IP.m` (returned unmodified there) are dropped.

## Toolbox policy

IP needs the Optimization Toolbox. Reference-mode eGSK requires
`license('test','Optimization_Toolbox') && exist('fmincon','file')`; when
unavailable, the default call fails with `egsk:fminconUnavailable` before the
search starts. Explicit opt-out via `options.use_fmincon = false` is kept only
for non-reference diagnostics and is recorded as
`'IP refinement disabled via options.use_fmincon (non-reference diagnostic mode)'`.

## Unknown optimum

The escape trigger compares against `optimum + val_2_reach`
(`val_2_reach = 1e-8` in the reference; `problem.target_error` plays that
role when set). With `problem.optimum = NaN` the target can never be
confirmed reached, so the trigger is treated as satisfied.

## Sanctioned modernizations / interface notes

- `rand('seed', sum(100*clock))` is replaced by `gsk_set_rng(options)`.
  Runner `seed_policy='reference'` uses the scheduled
  `base_seed + 9973*func + run - 1` seed with the legacy `seed` generator.
  Direct optimizer calls default to `twister`; `options.rand_generator` may
  select `threefry`, `twister`, legacy `seed`, or legacy `state` for
  diagnostics. Unified benchmark runs resolve to `threefry` when MATLAB
  supports it and fall back to `twister` otherwise. Wall-clock seeding is not
  supported.
- `result.error = best_fitness - optimum`, zeroed below
  `problem.target_error` -- exactly the reference driver rule
  (`bsf_error_val = bsf_fit_var - optimum`, zeroed below `val_2_reach`).
- Convergence recorded once per generation (the reference appends per
  evaluation; fmincon evaluations inside IP were never appended there
  either). Bookkeeping only.
- The reference never stops early, so `termination` is always
  `'max_evaluations'`.

Smoke test: `src/tests/test_egsk_smoke.m` (asserts reference-mode fmincon
requirements and the explicit non-reference opt-out path).
