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

Port of the DT-GSK reference implementation (Python, MIT license), v2.46,
<https://github.com/MostafaMassoud/DT-GSK>. Paper: Masoud, Roshdy, Mohamed,
"DT-GSK: Dimension-Tiered Adaptive Configuration Selection and Deterministic
Refinement for Gaining-Sharing Knowledge-Based Optimization Algorithm",
*Algorithms* (MDPI), 2026.

Only the `pub` profile is implemented; options no tier selects, research hooks
and telemetry are left out (listed in the `dt_gsk_optimize.m` header).

1. **Against the Python reference.** A first, line-by-line port was checked
   module by module and run against the unmodified Python code on identical
   random numbers in all four tiers: the same generations, evaluations and
   per-substream draw counts, and traces equal to 1e-11 until a last-bit
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

MATLAB's Threefry stream and the Python replica produce the same 64-bit words
but round them to doubles slightly differently (MATLAB keeps up to one more
bit below 0.5), so live runs differ from the Python runs by at most 2^-53 per
uniform draw; integer, permutation and mask draws coincide.

## CEC2017 campaign

Pending (filled in from `scripts/compare_reference_runs.m` when the campaign
completes).
