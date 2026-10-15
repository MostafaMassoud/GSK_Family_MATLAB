# ATMALS-GSK

MATLAB implementation of ATMALS-GSK: GSK with adaptive parameter selection
(probability tables + roulette wheel over value pools) and a best-solution
local search.

Entry point: `atmals_gsk_optimize.m` (`result = atmals_gsk_optimize(problem, options)`,
contract in `docs/reference/matlab_interface.md`).

## Historical Source Notes

```text
historical source: atmalsgsk/atmalsgsk/cec2017/ATMALS_GSK.m
historical source: atmalsgsk/atmalsgsk/cec2011/ATMALS_GSK.m
historical source: atmalsgsk/atmalsgsk/cec2017/ProbUpdate.m            (== cec2011 copy)
historical source: atmalsgsk/atmalsgsk/cec2017/RouletteWheelSelection.m (== cec2011 copy)
historical source: atmalsgsk/atmalsgsk/cec2017/boundConstraint.m        (== cec2011 copy)
historical source: atmalsgsk/atmalsgsk/cec2017/Gained_Shared_Senior_R1R2R3.m
historical source: atmalsgsk/atmalsgsk/cec2011/Gained_Shared_Senior_R1R2R3.m
```

## Files

- `atmals_gsk_optimize.m` -- both reference drivers transcribed line by line;
  local subfunctions `atmals_senior_r1r2r3_cec2017` (PartSize partition,
  intentionally not the shared `src/common` Senior helper, see below),
  `atmals_senior_r1r2r3_cec2011` (round(0.1/0.9) partition, no P argument)
  and `boundConstraint` (midpoint repair, byte-identical reference copies).
  The junior helper is the shared `src/common/Gained_Shared_Junior_R1R2R3.m`
  (identical behavior and RNG stream).
- `atmals_prob_update.m` -- faithful port of `ProbUpdate.m`.
- `atmals_roulette_select.m` -- faithful port of `RouletteWheelSelection.m`.
- `atmals_gaussmf.m` -- local replacement for the Fuzzy Logic Toolbox
  `gaussmf`: `y = exp(-(x-c).^2./(2*sig.^2))`, mathematically identical, so
  there is no toolbox dependency.

## Protocols

`options.protocol = 'cec2017'` (default) or `'cec2011'` selects which
reference driver behavior is reproduced. The two reference files differ in
exactly these transcribed points:

| Aspect | `cec2017` | `cec2011` |
|---|---|---|
| `G_Max` | `fix(max_nfes/np)` | `max_nfes/np` (no `fix`) |
| `Mean_Fit` signal | mean of best half of `abs(fitness - optimum)` | mean of best half of raw `fitness` (no known optima) |
| Senior partition | `(indBest, P_GSK)`: `PartSize = round(0.1*NP)`, middle block ends at `NP - PartSize` | local helper without `P`: blocks `round(NP*0.1)` / `round(NP*0.9)` |
| Local-search clip | exactly to bounds | to `bound + eps` / `bound - eps` |
| `D == 1` | n/a | dedicated senior-only branch (hard-coded factor 0.5, ratio 0.9) |

If `problem.optimum` is NaN under `'cec2017'`, the port falls back to the
raw-fitness signal (the cec2011 signal); the reference never ran the cec2017
driver with unknown optima.

`run_experiment` auto-selects `protocol='cec2011'` for ATMALS-GSK on the
CEC2011 suite and `protocol='cec2017'` on the CEC2017 suite. Direct calls may
still pass `options.protocol` explicitly.

## Preserved reference quirks (deliberate, do not "fix")

1. **RP update**: `RP = RP_Min + (RangeLS_Max - RangeLS_Min)*(g/G_Max)` --
   written with the LOCAL-SEARCH range constants (0.2 and 1e-10), not
   `RP_Max - RP_Min`. RP therefore grows from 3 to only ~3.2 over a run and
   `RP_Max = 5` is defined but never used.
2. **Local-search rows**: `randperm(pop_size)` is drawn into `iii_mat`
   (consuming RNG state) but the loop overwrites rows `1..NLS` of `ui`, not
   the randomly chosen rows. The draw is kept for RNG-stream fidelity.
3. **Fixed senior P**: the adaptive `P` is selected by roulette every
   generation but never consumed; the senior phase always uses `P_GSK = 0.1`
   (cec2017 file) or the hard-coded `round(0.1/0.9)` partition (cec2011 file).
4. **ProbUpdate internals** (`atmals_prob_update.m`): the gaussmf CENTER is
   the pool INDEX while the membership is evaluated at the pool VALUES; the
   exponential memory weights history row `j` with `alpha^j`, so the OLDEST
   row (the all-ones prior) has the LARGEST weight; the history matrices grow
   by one row per generation, unbounded.
5. The senior `cec2017` partition (`middle = PartSize+1 : NP-PartSize`) is
   kept variant-local because the shared `src/common` Senior helper uses
   `round(NP*(1-P))`, which differs whenever `NP*P` is an exact half-integer.

## Parameters (reference defaults)

`np = 100`, initial `KF/KR/K/P = 0.5/0.9/10/0.1`, pools
`KF_VAL = 0.2:0.1:0.8`, `KR_VAL = 0.85:0.01:1`, `K_VAL = 8:1:30`,
`P_VAL = 0.05:0.01:0.15`, `PLS_VAL = 1:0.1:2`, `alpha = 0.98`, `PLS = 1`,
`NLS = round(0.05*np)`, `RP_Min/RP_Max = 3/5`,
`RangeLS_Max/RangeLS_Min = 0.2/1e-10`. Overridable via `options`
(`np`, `kf_pool`, `kr_pool`, `k_pool`, `p_pool`, `pls_pool`, `protocol`).
An overridden `kf_pool` / `kr_pool` / `k_pool` / `p_pool` / `pls_pool` must
contain the hard-coded initial pick `0.5` / `0.9` / `10` / `0.1` / `1`
(the first-generation probability update looks it up in the pool); otherwise
`atmals_gsk:options` is raised before any RNG draw.

## Sanctioned modernizations / interface notes

- `gsk_set_rng(options)` centralizes RNG setup. Direct calls default to
  `twister`; `options.rand_generator` may select `threefry`, `twister`,
  deterministic legacy `seed`, or deterministic legacy `state`. Runner-level
  reference mode uses deterministic legacy `seed` for ATMALS-GSK. The
  historical wall-clock call is provenance only, not a supported run mode.
- `result.error` follows CEC2017 ATMALS absolute-error reporting on CEC2017:
  `abs(best - optimum)`, zeroed below `problem.target_error` (1e-8). For other known-optimum
  suites it follows the project interface (`best_fitness - optimum`, zeroed
  below `problem.target_error`); the CEC2011 driver recorded raw final fitness
  with no error concept.
- Convergence is recorded once per generation (interface), whereas the
  reference cec2017 driver appended per evaluation and the cec2011 driver per
  generation. Bookkeeping only; no RNG or trajectory impact.
- The reference per-child counter reads `max_nfes + 1` when a generation
  crosses the budget (`max_nfes` not a multiple of `np`, or below `np`);
  `result.nfes` and `convergence.nfes` are clipped at `max_nfes`. The loop
  counter and the crossing semantics are unchanged (only children within
  budget update the best-so-far). Bookkeeping only; no RNG or trajectory
  impact.
- The reference never stops early, so `termination` is always
  `'max_evaluations'`.

Smoke test: `src/tests/test_atmals_gsk_smoke.m` (both protocols, determinism,
interface contract; budget-crossing accounting for non-divisible and below-NP
budgets under both protocols; fair-start X0 reuse with the post-X0 RNG
restore; the cec2011 `D == 1` senior-only branch; pool-override validation).
