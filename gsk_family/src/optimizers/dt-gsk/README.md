# DT-GSK

MATLAB implementation of DT-GSK (Dimension-Tiered Gaining-Sharing Knowledge),
the seventh member of the family. DT-GSK keeps the GSK junior/senior
operators and switches its control machinery on by problem dimension.

Entry point: `dt_gsk_optimize.m` (`result = dt_gsk_optimize(problem, options)`,
contract in `docs/reference/matlab_interface.md`).

## Files

- `dt_gsk_optimize.m` — the whole optimizer: initialization, the generation
  loop (population reduction, ACE parameter selection, linkage crossover,
  DE entry, selection, ARGP, escapes and restarts, local search, final
  polish) and the result struct. Small helpers are local functions.
- `dt_gsk_config.m` — the published `pub` profile: every setting the
  optimizer uses, grouped by dimension tier.
- `dt_gsk_graph.m` — the interaction graph (SGSM) used from D = 50: learns
  which coordinates improve together and turns them into linkage blocks and
  the final-polish basis.

## Dimension tiers (`pub` profile)

| Tier | Mechanisms |
|---|---|
| D < 20 | ACE (one memory), NLPSR, ARGP, linkage crossover, stagnation-triggered escape with Cauchy kicks, archive, coordinate local search |
| 20 <= D < 50 | + top/bottom ACE memories, DE/rand/1 pool entry, KR floor, triple escape trigger |
| D >= 50 | + interaction graph (learned linkage), wider senior groups for the bottom half, final polish |
| D >= 100 | + TERRA budget policy, SP-NLPSR floor, basin-novelty restarts, late controllers (A1, A2, FC4); no DE entry |

A deep-stall full restart is active in every tier. The initial population is
always NP = 5*D.

## Behavior notes

- `options.seed` is required; `options.rand_generator` must be `threefry`
  (empty/`auto`/`default` accepted). All draws come from named Threefry
  substreams derived from the seed; the global RNG is never touched.
- Fair-start exception: DT-GSK samples its own initial population and ignores
  a runner-supplied X0. `run_experiment` schedules it with the unified seed
  `get_cec_seed(base_seed, dim, func, run)` and `threefry` under every
  `seed_policy`.
- Always runs the full budget (`termination = 'max_evaluations'`); the
  convergence trace is the best-so-far value after each generation.
- `error = best_fitness - optimum`, zeroed below `target_error`, NaN without a
  known optimum (project-wide rule).

## Source and validation

Port of the DT-GSK reference implementation v2.46 (MIT license),
<https://github.com/MostafaMassoud/DT-GSK>. Paper: Masoud, Roshdy, Mohamed,
"DT-GSK: Dimension-Tiered Adaptive Configuration Selection and Deterministic
Refinement for Gaining-Sharing Knowledge-Based Optimization Algorithm",
*Algorithms* (MDPI), 2026.

Only the `pub` profile is implemented; options no tier selects, research hooks
and telemetry are left out (listed in the `dt_gsk_optimize.m` header).

1. **Against the reference implementation.** A first, line-by-line port was
   checked module by module and run against the unmodified reference
   implementation on identical random numbers in all four tiers: the same
   generations, evaluations and per-substream draw counts, and traces equal to 1e-11 until a last-bit
   floating-point difference crosses a discrete decision (exact ties, one-ulp
   improvements). The reference's byte-stable golden values (seed 12345,
   3,000 evaluations) are reproduced to 1e-13; `src/tests/test_dt_gsk_smoke.m`
   checks the sphere cells.
2. **This compact version against that port.** These three files reproduce the
   line-by-line port bit for bit (best_x, best_fitness, nfes and the full
   convergence trace) on 25 CEC2017/sphere runs covering every tier at full
   budgets, plus 42 problems aimed at rare branches and 84 interface checks,
   while running 1.3x to 7x faster.
3. **Full CEC2017 campaign** against the imported reference results
   (`benchmarks/cec_reference_results/cec2017/dt-gsk/`): see below.

MATLAB's Threefry generator produces the same 64-bit words as the reference
implementation's generator but rounds them to doubles slightly differently
(MATLAB keeps up to one more bit below 0.5), so live runs differ from the
reference runs by at most 2^-53 per uniform draw; integer, permutation and mask
draws coincide.

## CEC2017 campaign

Same protocol as the imported reference runs: 51 runs per function, F2
excluded, the full budget of 10,000 x D evaluations, and the same seed for
every run (`get_cec_seed(20240620, D, F, run)`, Threefry). Results are written
to `results/_run_all/dt-gsk/cec2017/`; `results/` is local output and is not
in the repository, so rerun `run_all_cec2017.m` with `optimizers = {'dt-gsk'}`
to reproduce them.

**Status (2026-10-16):** D10, D30 and D50 are complete (87 functions, 4,437
runs, about 51 CPU hours). D100 is paused and has not been run yet.

**Result: the MATLAB runs match the reference runs.** Each function was
compared with `scripts/compare_reference_runs.m`: two-sided Wilcoxon rank-sum
test at p = 0.05, and Best, Median and Mean within one order of magnitude, with
both sides rounded to the 11 significant digits of the reference file.

| D | Functions | Match | Rank-sum p < 0.05 | Lowest rank-sum p |
|---|---|---|---|---|
| 10 | 29 | 28 | 0 | 0.63 |
| 30 | 29 | 29 | 0 | 0.33 |
| 50 | 29 | 28 | 0 | 0.48 |

- No function differs significantly, before or after Holm correction.
- `gsk_validate --verify` reports CONSISTENT (87 functions, 0 hard failures).
- Two functions differ only in Best (Median and Mean agree, rank-sum p >= 0.94).
  Best is the minimum of 51 runs, so one lucky run decides it; neither case
  points to a porting error:
  - D10 F26: 50 of 51 runs end at error 300 on both sides. The one run that
    escapes reaches 0 in MATLAB and 200 in the reference, so Best is 0 vs 200.
  - D50 F4: 6 to 7 runs per side reach the global basin. The reference's best
    run is a lone 3.9e-6 (its next best is 5.3e-4); MATLAB's best is 7.6e-4.
- The paired signed-rank test (informational; both sides use the same seeds)
  is significant after Holm correction in one function, D50 F9. There, 37 of
  51 runs are identical and the other 14 differ only in the 11th significant
  digit (0.089528250416 vs 0.089528250417): the same final value, rounded on
  either side of a digit.

**To finish D100**, open `run_all_cec2017.m`, set `optimizers = {'dt-gsk'}`,
`dimensions = [100]`, `use_parallel = true` and `overwrite = false`, start a
pool with about 8 workers first (see `RUNBOOK.md`, section 5), and press Run.
Finished runs are kept, so it can be stopped and resumed at any time. Expect
roughly 7 to 13 hours on 8 workers. Then compare all 116 functions:

```matlab
compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
    'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv');
```
