# Benchmark Protocol

> **What this is:** the per-suite protocol for the five CEC benchmark suites -
> functions, dimensions, domains, optima, budgets, and statistics conventions -
> as reflected by the committed implementation. **For:** anyone running a suite
> or interpreting its error/raw-objective statistics. **Prerequisites:** none.
> **After reading** you will know each suite's matrix and how errors are computed
> and zeroed.

Protocols reflected by the committed implementation. Budgets and target
errors are implemented in `src/runners/gskcec_make_problem.m` (MATLAB
side) and the per-suite headers under
`benchmarks/cec_suite_cpp/cec_tools/include/gskcec/benchmark/` (C++ side).

Layout reminder:

```text
benchmarks/cec_reference_results/  imported reference tables + curated curves/logs (read-only)
benchmarks/cec_suite_cpp/              CEC C++ ports, input data, and support tools
benchmarks/cec_suite_cpp/cec_tools/    C++ CEC helper library, CLI tools, tests
```

CEC benchmark implementations are standalone C++20 (no MATLAB/R/MEX
at runtime). GSK-family optimizers remain MATLAB.

## Statistics conventions (all suites)

- `best/median/mean/worst/sd` over runs; `sd` is the sample standard
  deviation.
- Suites with known optima (cec2017, cec2020, cec2013): statistics are
  computed over errors `best_fitness - optimum`; ATMALS-GSK on CEC2017 uses
  `abs(best_fitness - optimum)` error with the standard `1e-8` zero cutoff.
  Other reference target-error rules zero errors below 1e-8 exactly where the
  reference drivers do (see `docs/reference/porting_notes.md` per optimizer).
- Suites without published optima (cec2011, cec2013lsgo*): statistics are
  computed over raw objectives. On cec2011 (`optimum()` is NaN) the per-run
  `error` column is NaN. (*LSGO optima are 0 by construction and the port's
  `optimum()` returns `0`, so its per-run `error` column holds
  `best_fitness - 0`, i.e. the raw objective, with no zero cutoff; the imported
  DECC-G/MOS tables report raw objective values, so raw objectives are used
  for comparability.)
- Generated results never compare raw fitness against error columns;
  the comparison tool matches function labels case-insensitively
  (`1` == `F1` == `f1`).

## CEC2017

- Provenance: CEC2017 competition source and committed CEC2017 input data.
- Functions 1..30; dimensions 10, 30, 50, 100; domain [-100,100]^D.
- Optimum: `100 * function_id`. Budget: `10000 * D`. Target error: 1e-8.
- F2 is implemented and validated but excluded from default comparisons
  (reference protocol).

## CEC2020

- Source: `benchmarks/cec_suite_cpp/cec2020/`, with AGSK-compatible public
  function mapping, optima, and budgets documented in `docs/reference/porting_notes.md`.
- Public functions 1..10 (internal mapping {1,2,3,7,4,16,6,22,24,25});
  dimensions 5, 10, 15, 20; domain [-100,100]^D.
- Optimum vector (AGSK source): [100, 1100, 700, 1900, 1700, 1600, 2100,
  2200, 2400, 2500]. Target error: 1e-8.
- Budgets: D5 50,000; D10 1,000,000; D15 3,000,000; D20 10,000,000.
- Reference data gaps: public functions 1 and 8 lack shuffle data at D=5
  and D=15; those cells raise explicit errors / are reported as SKIPs.

## CEC2013 (standard)

- Source: converted CEC2013 R package material preserved under
  `benchmarks/cec_suite_cpp/cec2013/` (runs without R).
- Functions 1..28; dimensions 2, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90,
  100; domain [-100,100]^D.
- Optima: biases -1400..-100 (f1..f14) and 100..1400 (f15..f28).
- Budget: `10000 * D`; target error 1e-8 (GSK driver convention).
- Validation: `gsk_validate --suite cec2013 --against saved_vectors`
  (analytic + optimum-at-shift + self-generated regression baseline; no R
  ground truth available locally - see porting notes).

## CEC2013LSGO

- Source: `.../cec_suite_cpp/cec2013lsgo/` (separate large-scale suite; never
  merged with standard CEC2013; only the C++ sources are kept).
- Functions 1..15; native dimensions 1000 (905 for overlapping f13/f14);
  per-function domains from the code ([-100,100] / [-5,5] / [-32,32]).
- Optimum 0 by construction (f12: optimum at xopt+1; f14: no single
  optimum point - see porting notes).
- Budget: 3,000,000 evaluations (LSGO competition protocol, matching the
  imported DECC-G and MOS reference tables under
  `benchmarks/cec_reference_results/cec2013lsgo/`). No target-error rule.
- Available through CLI/configs/tests; not part of the default GSK matrix.

## CEC2011

- Source: `.../cec_suite_cpp/cec2011/` (MATLAB real-world problems, ported;
  runs without MATLAB).
- Problems 1..22 (GSK numbering); fixed native dimensions
  {6, 30, 1, 1, 30, 30, 20, 7, 126, 12, 120, 240, 6, 13, 15, 40, 140,
  96, 96, 96, 26, 22}; per-problem, per-coordinate bounds (problem 12
  contains 24 zero-width ranges).
- No published optima: `optimum()` is NaN, statistics over raw objectives.
- Budget: 150,000 evaluations (GSK reference drivers). No target error.
- Suite-level reference rules preserved: NaN objectives become 0
  (`Calc_Fitx_2011` rule; +/-Inf passes through); problems 11-20 round
  inputs to 4 decimals (half away from zero) before evaluating.
- The official CEC2011 technical report numbering (T01..T13 with
  sub-cases) maps to the GSK 1..22 numbering as documented in
  `docs/reference/cec2011_port_plan.md`.

## Budgets and population sizes across optimizers

Budgets and target errors are suite properties (`gskcec_make_problem.m`), so
every optimizer, DT-GSK included, runs against the same `max_nfes` for a given
`(suite, function, dimension)` cell. What differs is how an optimizer spends
it: AGSK and APGSK stop early on the `1e-8` target; the others, DT-GSK
included, always use the full budget. The initial population is algorithm
behavior: `NP = 100` is the interface default of the six runner-`X0`
optimizers, while DT-GSK starts from `NP = 5*D` (for example 50 at CEC2017
D=10, 500 at D=100, 5000 at CEC2013LSGO D=1000) and reduces it nonlinearly
toward its tier's `n_min` during the run.

## Default experiment matrix

See `src/experiments/default_experiment_matrix.m`: all seven optimizers
(including dt-gsk) on cec2017 and cec2011; agsk additionally on cec2020.
DT-GSK's imported reference tables also cover cec2013, cec2013lsgo, and
cec2020, which it runs on request. That function is a
reference statement with no callers; the executable form of the default matrix
is `configs/all_cec2017.yml`, `configs/all_cec2011.yml` and
`configs/agsk_cec2020.yml` (run via `gsk_run` or `scripts/run_all.ps1 -Full`),
and the root `run_all_cec*.m` launchers carry their own CONFIG lists. cec2013 and
cec2013lsgo are validation/extension suites, runnable on request.
Optimizer/suite pairings the reference sources never ran (e.g. fdb-agsk
on CEC suites) are framework-level extensions, not reproductions.

## Worked protocol examples

**CEC2017 error calculation.** For CEC2017 function 7, the known optimum is:

```text
optimum = 100 * function_id = 700
```

If a run returns `best_fitness = 721.35`, the reported error is:

```text
error = best_fitness - optimum = 721.35 - 700 = 21.35
```

If a run returns `best_fitness = 700 + 4e-9`, the error is below the `1e-8`
zero cutoff and is reported as `0` in summary statistics.

**CEC2017 budget calculation.** For `D = 30`:

```text
max_nfes = 10000 * D = 300000
```

With `NP = 100`, initialization consumes 100 evaluations. In baseline GSK,
`G_Max = fix(300000 / 100) = 3000`; the reference still derives the generation
schedule from the full budget, not from the post-initialization remainder.

DT-GSK on the same cell gets the same `max_nfes = 300000` but starts from
`NP = 5 * 30 = 150` (150 initialization evaluations, the `20 <= D < 50` tier).
Its population shrinks toward `n_min = 12` along the NLPSR schedule
`NP = NP_init + (n_min - NP_init) * frac^(1 - frac)`, where `frac` is the
fraction of the budget already spent, and the run ends at exactly
`nfes = 300000`.

**CEC2011 raw objective convention.** CEC2011 has no published optimum vector in
this project. If problem 5 returns `best_fitness = -23.0`, the summary mean is
computed directly over raw objective values. The `error` field in per-run logs is
`NaN`, not `best_fitness - 0`.

**MATLAB comparison table tolerance.** The console comparison table printed by
`run_experiment` uses:

```text
Delta(New-Old) = generated_mean - reference_mean
```

If `abs(Delta(New-Old)) < 1e-8`, the delta is displayed as `0.00E+00` and the row
is counted as equal. This is a reporting tolerance only; it does not change
stored objective values, seeds, budgets, or optimizer behavior.
