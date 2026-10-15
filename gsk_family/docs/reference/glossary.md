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
  generation. Baseline GSK default `100`.

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
  (CEC2011; CEC2013LSGO as imported) report **raw objectives**, and the `error`
  column is `NaN`.
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
  (`doxygen docs/Doxyfile`); see [api.md](api.md). The project uses **no** Python
  documentation tooling.
- **Graphviz / dot.** An optional graph-drawing tool Doxygen can call to render
  call graphs. If `dot` is not installed, the API docs still build (set
  `HAVE_DOT=NO`).

## The three CLI tools

- **`gsk_list`.** Enumerates the benchmark suites (with their functions and
  dimensions), the six optimizers, and the imported reference tables.
- **`gsk_validate`.** Validates reference tables, smoke-tests a suite
  (`--suite <name> --smoke`), runs the CEC2013 saved-vector check, compares
  generated results against references (`--compare`), and re-runs the per-run
  verdict (`--verify`).
- **`gsk_run`.** Orchestrates an experiment: validates the request, drives MATLAB
  to run the optimizer(s), and automatically verifies each run (opt out with
  `--no-verify`).
