# FDB-AGSK

MATLAB implementation of FDB-AGSK: the adaptive GSK (AGSK) machinery with
Fitness-Distance Balance (FDB) guide selection injected into the junior /
senior donor indices. All five reference injection cases are implemented.

Entry point: `fdb_agsk_optimize.m` (`result = fdb_agsk_optimize(problem, options)`,
contract in `docs/reference/matlab_interface.md`).

## Historical Source Notes

```text
historical source: FDB-AGSK reference FDB_AGSK_Case1.m
historical source: FDB-AGSK reference FDB_AGSK_Case2.m
historical source: FDB-AGSK reference FDB_AGSK_Case3.m
historical source: FDB-AGSK reference FDB_AGSK_Case4.m
historical source: FDB-AGSK reference FDB_AGSK_Case5.m
historical source: FDB-AGSK reference FDB_Func1.m
historical source: FDB-AGSK reference FDB_Func2.m
historical source: FDB-AGSK reference RFDB_Func1.m
historical source: FDB-AGSK reference problem.m            (sphere harness)
historical source: FDB-AGSK reference problem_terminate.m  (D = 100, maxFEs = 1000*D)
```

The five Case files are self-contained (each embeds its own
`Gained_Shared_Junior_R1R2R3`, `Gained_Shared_Senior_R1R2R3` and
`boundConstraint` subfunctions); the AGSK machinery was transcribed from the
Case files themselves, and the per-case junior/senior subfunctions are
reproduced as case-parameterized local subfunctions of `fdb_agsk_optimize.m`.

## Files

- `fdb_agsk_optimize.m` -- main port with local subfunctions
  `fdb_junior_r1r2r3`, `fdb_senior_r1r2r3` (case-parameterized faithful
  transcriptions) and `boundConstraint`.
- `fdb_score_best.m` -- port of `FDB_Func1.m`: Manhattan distance to the
  current best, normalized fitness `1-(f-min)/(max-min)`, normalized
  distance, `score = normFitness + normDistance`, ARGMAX index. Flat-fitness
  degenerate branch returns `randi(NP)` (consumes one RNG draw), as written.
- `fdb_score_roulette.m` -- port of `RFDB_Func1.m`: same score, roulette-wheel
  index; extended degenerate guard
  `(min==max) || (sum(fitness)>=Inf) || ~(sum(best)<inf)`, as written.
- `fdb_score_ranking.m` -- port of `FDB_Func2.m` (differs materially from
  FDB_Func1: returns the FULL index ranking sorted by descending score).
  Preserved quirk: in the degenerate branch it draws `randi` into a variable
  that is not the output, returning an EMPTY ranking (the Case2 caller would
  error, exactly like the reference).

## Case injections (`options.fdb_case`, default 1)

Case 1 is the default because it is the first/canonical case of the
reference set; all five remain available.

| Case | Scoring call(s) per generation | Junior (Rg1/Rg2/Rg3) | Senior (R1/R2/R3) |
|---|---|---|---|
| 1 | `FDB_Func1` | standard (ring neighbors + random R3) | R2 = FDB-best index (same for every row); R1/R3 sampled from best/worst 5% |
| 2 | `FDB_Func2` | standard | R3 sampled from the TAIL of the FDB descending ranking (`round(NP*0.95)+1..NP`); R1/R2 standard |
| 3 | `FDB_Func1` then `RFDB_Func1` | R2 = RFDB roulette index, R3 = FDB-best index (constants overwriting the ring values) | standard (0.05 / middle / 0.95) |
| 4 | `FDB_Func1` then `RFDB_Func1` | R1 = RFDB roulette index, R3 = FDB-best index | standard |
| 5 | `FDB_Func1` | R3 = FDB-best index | standard |

In cases 3-5 the junior collision loop (`R3 == R0/R1/R2`) then re-randomizes
the injected constant index at collision positions -- exactly as the
reference (the constant-index injections are therefore partially
re-randomized wherever they collide).

## Transcribed AGSK machinery (from the Case files)

- Current interface default `np_init = 100`; the reference
  `problem_terminate` harness value `40*problem.dim` is opt-in via
  `options.np_init`. `min_pop_size = 12`; nonlinear reduction
  `plan = round((min-max)*((nfes/max_nfes)^(1-nfes/max_nfes)) + max)`,
  removing the current worst individual one at a time (the per-individual
  knowledge-rate column `K` is trimmed alongside).
- `KF_pool = [0.1 1.0 0.5 1.0]`, `KR_pool = [0.2 0.1 0.9 0.9]`; setting
  probabilities `[0.85 0.05 0.05 0.05]` while `nfes < 0.1*max_nfes`, then
  `KW_ind = 0.95*KW_ind + 0.05*All_Imp` (normalized) with the 0.05 floor /
  largest-gets-remainder redistribution.
- Per-individual `K`: uniform(0,1) with prob 0.5, integer `ceil(20*rand)`
  with prob 0.5; `D_junior = ceil(D*(1-nfes/max_nfes).^K)`.
- Reference budget-crossing counter semantics: the internal per-child counter
  may read `max_nfes + 1` when a generation crosses the budget
  mid-population. `result.nfes` and `convergence.nfes` are clipped at
  `max_nfes` (bookkeeping only; the internal counter that drives the KW
  phase, the junior schedule and the resize plan is unchanged).

## Preserved quirks / usage notes

- The reference Case files never record the best-so-far SOLUTION during the
  initial population scan (only its fitness); this port records it there so
  `result.best_x` is always defined. Pure bookkeeping -- no RNG draw or
  search-trajectory change (the reference would crash at its final
  `disp(bsf_solution)` if no child ever improved on the initial best).
- The adaptive probability branch requires `np_init < 0.1*max_nfes` in the
  original reference flow (true for `40*D` vs `1000*D`). This port includes an
  `isempty(KW_ind)` phase guard so reduced-budget runs are robust; the guard is
  inert on validated full-budget runs where the `nfes` condition fires first.
- `dif_val` is computed and never used, as written.
- The reference cases run on a simple sphere problem (`problem.m`); running
  FDB-AGSK on CEC suites through the generic `problem` interface is a
  framework-level extension of this port, not a reference-validated setup.

## Sanctioned modernizations / interface notes

- Deterministic seeding via `gsk_set_rng(options)` (the reference relies on the
  MATLAB session RNG state). Runner `seed_policy='reference'` uses
  `D*func*run` and the legacy `seed` generator for this AGSK-family variant.
- The reference tracks no optimum/error; `result.error` follows the
  interface contract (`best_fitness - optimum`, zeroed below
  `problem.target_error`, NaN for unknown optimum).
- Convergence recorded once per generation; `termination` is always
  `'max_evaluations'` (the reference never stops early).
- The reported `result.nfes` / `convergence.nfes` are clipped at `max_nfes`
  although the reference counter can read `max_nfes + 1` (see above).
  Bookkeeping only; no RNG or trajectory impact.

Smoke test: `src/tests/test_fdb_agsk_smoke.m` (default config, all five
cases briefly, invalid-case rejection, determinism, budget accounting).
