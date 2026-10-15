# Glossary

> **What this is:** Concise definitions of the terms used across this MATLAB +
> C++ project -- the GSK-family algorithms, the CEC suites, the statistics, and
> the C++ tooling. **For:** anyone who hits an unfamiliar acronym while reading
> the other pages. **Prerequisites:** none. **After reading:** you can decode the
> vocabulary in [architecture.md](architecture.md),
> [benchmark_protocol.md](benchmark_protocol.md), and the algorithm pages.

Acronyms are expanded on first use. For the narrative behind these ideas, read
[../getting-started/explainer.md](../getting-started/explainer.md); for the exact
protocol rules, see [benchmark_protocol.md](benchmark_protocol.md).

## Algorithms (the GSK family)

- **GSK — Gaining-Sharing Knowledge.** The baseline population-based optimizer
  this project is built around. It improves a population of candidate solutions
  using two "knowledge" phases — junior (learning from near-rank neighbors) and
  senior (learning from best/middle/worst groups). Implemented in
  `src/optimizers/gsk/gsk_optimize.m`.
- **AGSK — Adaptive GSK.** A GSK variant that *adapts* its control settings
  during a run (it adjusts the mix of knowledge behaviors and shrinks the
  population over time) instead of using fixed values. `src/optimizers/agsk/`.
- **APGSK — Adaptive-Parameters GSK.** A GSK variant with a much larger
  reference NP (e.g. `200 × D`), a sign-switchable (positive/negative) knowledge
  factor, and a stochastic pool-based schedule for its step size.
  `src/optimizers/apgsk/`.
- **ATMALS-GSK — Adaptive Tuning + Memory + Adaptive Local Search GSK.** A GSK
  variant that adds memory-based adaptive parameter selection and an adaptive
  local-search refinement step; in this project it has two reference protocols
  selectable via `options.protocol` (`'cec2017'` or `'cec2011'`).
  `src/optimizers/atmals-gsk/`.
- **eGSK — enhanced GSK.** A GSK variant with a late-stage refinement that uses
  `fmincon` (an SQP local solver) to polish the best solution. Reference-mode
  eGSK requires MATLAB's Optimization Toolbox; `use_fmincon=false` is only an
  explicit non-reference diagnostic mode. `src/optimizers/egsk/`.
- **FDB-AGSK — Fitness-Distance-Balance AGSK.** An AGSK variant that selects some
  donor candidates using a **Fitness-Distance-Balance (FDB)** score (which blends
  how good a candidate is with how far it is from the best) instead of pure
  ranking. Five selectable cases; default `fdb_case = 1`.
  `src/optimizers/fdb-agsk/`.
- **DT-GSK — Dimension-Tiered GSK.** The seventh optimizer, a MATLAB port of
  the DT-GSK reference implementation v2.46 (MIT license). It keeps the
  GSK junior/senior operators and switches its control machinery (ACE, ARGP,
  NLPSR, BSE, SGSM, TERRA and local refinement, below) on by **dimension
  tier**. It starts from `NP = 5 × D`, always uses the full budget, and is
  **unified-only** (below). `src/optimizers/dt-gsk/`; behavior and validation
  in its `README.md`; algorithm page [../algorithms/dt-gsk.md](../algorithms/dt-gsk.md).

## GSK mechanics

- **Junior knowledge (junior gaining-sharing).** The phase where each individual
  learns from its **near-rank neighbors** — the candidate just better than it in
  the ranking, the one just worse, and one random other candidate. Produces
  small, local, exploratory moves.
- **Senior knowledge (senior gaining-sharing).** The phase where the ranked
  population is split into **best / middle / worst** groups and each individual
  is nudged by combining representatives from those groups. Produces larger,
  structured, exploitative moves.
- **KF — Knowledge Factor.** The step-size scalar: how far to move along the
  direction the neighbors/groups suggest. Baseline GSK default `0.5`.
- **KR — Knowledge Ratio.** The probability that any given coordinate (knob)
  actually adopts its proposed new value rather than keeping the old one.
  Baseline GSK default `0.9`.
- **K — Knowledge Rate.** The exponent of the schedule that shifts each
  individual from mostly-junior behavior early in the run to mostly-senior
  behavior later. Baseline GSK default `10`.
- **NP.** The population size — the number of candidate solutions carried each
  generation. Baseline GSK default `100`; DT-GSK starts at `5 × D`.

## DT-GSK mechanisms

- **Dimension tier.** The dimension band that fixes which DT-GSK mechanisms
  run and with which settings: `D < 20`, `20 ≤ D < 50`, `D ≥ 50`, and `D ≥ 100`
  (each tier adds to the previous one). The settings are the published **`pub`
  profile**, `dt_gsk_config.m`.
- **ACE — Adaptive Configuration Engine.** Draws a `(KF, KR, Kexp)` setting per
  individual from a small pool and learns the pool probabilities from the
  fitness changes each entry produces (separate top-half and bottom-half
  memories from `D ≥ 20`; a DE/rand/1 pool entry for `20 ≤ D < 100`).
- **ARGP — Acceptance-Rate Gated Pool Pruning.** Freezes ACE pool entries whose
  rolling acceptance rate falls below a tier threshold after a warm-up share of
  the budget.
- **NLPSR — Nonlinear Population Size Reduction.** Shrinks the population from
  `5 × D` toward a floor `n_min` (12; 25 from `D = 50`) along a nonlinear
  schedule. **SP-NLPSR** (`D ≥ 100`) keeps a higher floor until the learned
  linkage has enough samples or 70% of the budget is spent.
- **BSE — Budget-Safe Escape.** The stagnation response: Cauchy kicks on the
  worst rows, then an archive-seeded partial restart, capped so it never
  overshoots the budget (from `D ≥ 20` the trigger also needs low acceptance
  and low diversity). A separate deep-stall full restart runs in every tier.
- **SGSM — Success-Graph Structural Memory** (also called interaction-structure
  memory, ISM). The `D ≥ 50` interaction graph (`dt_gsk_graph.m`): it learns
  which coordinates improve together, turns them into linkage blocks for the
  crossover, and gives the basis of the final polish. A component of DT-GSK,
  not its name.
- **TERRA.** The `D ≥ 100` budget policy (from the TERRA-GSK prototype in the
  reference code): the endgame local search runs only once 70% of the budget
  is spent, judged before the generation's escape step spends evaluations.
  The same tier adds basin-novelty restarts and the late controllers A1
  (late-acceptance clipping), A2 (frozen-streak KR broadening), and FC4
  (learned/random linkage mixing).
- **Final polish.** A one-shot deterministic compass search from the incumbent
  along the SGSM eigenbasis, at 96% of the budget (`D ≥ 50`); it complements
  the endgame coordinate local search on the elites (every tier).
- **Unified-only.** DT-GSK always gets the unified seed
  `get_cec_seed(base_seed, dim, func, run)` and `threefry`, whatever
  `seed_policy` is requested, and samples its own initial population instead
  of the runner's fair-start `X0` (the documented fair-start exception). See
  [seed_policy.md](seed_policy.md).

## Problem and run terminology

- **Black-box continuous optimization.** Finding the real-valued inputs that
  minimize an objective you can only *evaluate* (query for a score), not inspect
  or differentiate. See [../getting-started/explainer.md](../getting-started/explainer.md) section 1.
- **Dimension (D).** The number of decision variables (knobs) in a problem.
- **Function evaluation (one "evaluate").** A single query of the objective: feed
  in one candidate solution, get back one score.
- **nfes — number of function evaluations.** A running count of how many
  evaluations have been spent. The **budget** (`max_nfes` / `max_evaluations`) is
  the maximum allowed; for CEC2017 it is `10000 × D`.
- **Optimum / bias.** The true best (lowest) objective value of a function. For
  the synthetic CEC suites the designers set it to a known constant (often called
  the function's *bias*) — e.g. CEC2017 function `N` has optimum `100 × N`, and
  CEC2013 uses biases in the ranges −1400…−100 and 100…1400.
- **Error vs raw objective.** **Raw objective** is the score the function returns
  as-is. **Error** is `raw_objective − optimum`, the distance above the known
  best; it is the headline metric for suites with a known optimum (smaller is
  better, 0 is perfect), with values below the target threshold (`1e-8`) zeroed
  exactly as the reference drivers do. Suites *without* a published optimum
  (CEC2011; CEC2013LSGO as imported) report **raw objectives**; the `error`
  column is `NaN` on CEC2011 and equals the raw objective on CEC2013LSGO (its
  optimum is 0 by construction).
- **Convergence curve.** Best-so-far score (or error) plotted against `nfes`.
  The median run's trace is recorded per (function, dimension) in
  `curves/Figure_F<f>_D<d>_Run#<r>.csv`.
- **Reduced vs full protocol.** A run is **reduced** when it overrides the budget
  *or* uses fewer than 25 runs (e.g. the smoke config). Under a reduced protocol
  the gross-deviation check and the win/tie/loss tally in verification become
  *informational*, because a short run is legitimately worse than the published
  full-budget tables. A **full** protocol run uses the suite's standard budget
  and run count, and the strict checks apply.

## The benchmark suites

- **CEC.** The **Congress on Evolutionary Computation**, whose published problem
  sets are the field's standard benchmark yardstick.
- **CEC2011.** 22 real-world engineering problems (power-system scheduling,
  spacecraft trajectories, signal design, …) with fixed per-problem dimensions
  and **no published optima** (statistics over raw objectives). Budget 150,000
  evaluations.
- **CEC2013.** The standard 28-function synthetic single-objective suite,
  dimensions 2…100, domain `[-100,100]^D`, optima given as biases, budget
  `10000 × D`, target error `1e-8`.
- **CEC2013LSGO.** The **Large-Scale Global Optimization** suite: 15 functions at
  native dimension ≈1000 (905 for the overlapping F13/F14). Optimum is 0 by
  construction; the imported reference tables report raw objectives. A separate
  suite from standard CEC2013 — the two are never merged. Budget 3,000,000
  evaluations.
- **CEC2017.** The widely-used 30-function 2017 single-objective suite,
  dimensions 10/30/50/100, domain `[-100,100]^D`, optimum `100 × function_id`,
  budget `10000 × D`, target error `1e-8`. (Function 2 is implemented and
  validated but excluded from default comparisons, per the reference protocol.)
- **CEC2020.** A compact 10-function 2020 suite, dimensions 5/10/15/20. Its
  optima are a specific reference vector (not `100 × id`), and its budgets are
  large and dimension-specific (D5 50k, D10 1M, D15 3M, D20 10M).

## Statistics and verification

- **best / median / mean / worst / sd.** The summary statistics reported across a
  set of runs (over errors when an optimum is known, else raw objectives). `sd`
  is the **sample standard deviation** (spread of the results).
- **Wilcoxon (signed-rank test).** A non-parametric statistical test comparing
  **two** algorithms across matched problems, to judge whether one is
  significantly better. The per-run verification reports an informational
  "Wilcoxon-style" win/tie/loss tally against the reference.
- **Wilcoxon rank-sum test and Holm adjustment.** The unpaired two-sample test
  that `scripts/compare_reference_runs.m` applies per (dimension, function) cell
  to two sets of runs (e.g. a MATLAB DT-GSK campaign and the imported
  reference runs); Holm's step-down method adjusts its p-values for the number
  of cells compared.
- **Friedman (test / ranking).** A non-parametric test that ranks **several**
  algorithms across many problems at once, producing an average rank per
  algorithm. Used in cross-algorithm comparison reporting.
- **Ground truth.** The reference-correct numbers used to check a port: fixed
  probe points evaluated by the **original** reference implementation, against
  which the C++ ports must agree (the largest CEC2017 deviation observed is
  ~`4.8e-15`).
- **Fidelity.** How faithfully a port reproduces its reference — both the
  numbers (checked against ground truth) and the deliberately preserved
  **quirks**. The per-suite fidelity record is [porting_notes.md](porting_notes.md).
- **CONSISTENT / DEVIATES verdict.** The automatic per-run conclusion
  (`verification.json`) of whether a run is consistent with the same optimizer's
  published reference table. **CONSISTENT** = no hard-failure check fired;
  **DEVIATES** = at least one did (and `gsk_run` exits nonzero). The
  hard-failure checks target implementation bugs — non-finite statistics, an
  impossible negative error, and (full protocol only) gross deviation — not
  optimization quality. See [result_schema.md](result_schema.md).

## Tooling and integration

- **MEX — MATLAB Executable.** A compiled C/C++ function callable from MATLAB.
  The original CEC functions shipped as MEX files; this project re-implements them
  in standalone C++ and bridges MATLAB to those C++ ports through the optional
  `gskcec_eval` MEX bridge (`scripts/build_mex_bridge.ps1`). The benchmark library
  itself never requires MATLAB or MEX.
- **CMake.** The build-system generator used to compile the C++ tooling
  (`cmake -S . -B build …`).
- **CTest.** CMake's test runner; `ctest --test-dir build --output-on-failure`
  runs the C++ unit tests and prints failing-test output.
- **Doxygen.** The documentation generator for the C++ public API headers
  (`doxygen docs/Doxyfile`); see [api.md](api.md).
- **Graphviz / dot.** An optional graph-drawing tool Doxygen can call to render
  call graphs. If `dot` is not installed, the API docs still build (set
  `HAVE_DOT=NO`).

## The CLI tools

- **`gsk_list`.** Enumerates the benchmark suites (with their functions and
  dimensions), the seven optimizers, and the imported reference tables.
- **`gsk_validate`.** Validates reference tables, smoke-tests a suite
  (`--suite <name> --smoke`), runs the CEC2013 saved-vector check, compares
  generated results against references (`--compare`), and re-runs the per-run
  verdict (`--verify`).
- **`gsk_run`.** Orchestrates an experiment: validates the request, drives MATLAB
  to run the optimizer(s), and automatically verifies each run (opt out with
  `--no-verify`).
- **`gsk_bench`.** Times raw benchmark `evaluate()` throughput on
  representative cells (see [performance.md](../research/performance.md)).
