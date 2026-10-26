# Validation Report

> **What this is:** a snapshot of what the automated checks currently verify in
> the `gsk_family` project, the commands that reproduce that state, and what
> validation work is still outstanding.
> **For:** reviewers and researchers who need to know how far the MATLAB
> optimizers and the C++ benchmark ports have been verified before relying on
> them.
> **Prerequisites:** [Reproducibility](reproducibility.md) for the run and build
> procedure; [Researcher Handbook](researcher_handbook.md) for evidence commands;
> [the glossary](../reference/glossary.md) for terms.
> **After reading:** you will know the coverage of the two test layers, the
> verification commands, the current pass status (framed honestly), and the
> remaining work.

This report records the current validation state of the project. It keeps two
senses of "correct" deliberately separate: benchmark **ports** are checked
*exactly* against fixed-vector ground truth; **optimizers** are checked
*statistically* against their published tables.

## Current Automated Validation

Validation runs at two layers.

**C++ benchmark ports (exact, fixed-vector ground truth).** The CEC ports are
standalone C++20 with no MATLAB, R, or MEX at benchmark runtime. The
`ctest` suite covers:

- the core library and RNG;
- imported reference-table loading, including `N/A` cells (on the current tree
  `gsk_list --references` loads 165 files / 1411 rows; the DT-GSK `evidence/`
  subfolder is not a table and is skipped);
- CEC2017 against 600 ground-truth rows (rel-tol `1e-10`, max deviation
  about `4.8e-15`);
- CEC2020 against 180 rows (max deviation about `2.8e-16`);
- CEC2013 against analytic checks, optimum-at-shift, and a self-generated
  regression baseline at `1e-12`;
- CEC2013LSGO against side-by-side reference agreement at the probe points;
- CEC2011 work packages A/B/C plus integration;
- the experiment-comparison code;
- a `gsk_bench` smoke run so the timing harness cannot rot;
- the CLI exit codes and argument parsing (`gskcec_cli_exit_codes`, against stub
  MATLAB executables) - 13 `ctest` suites in all.

**MATLAB optimizers and runner (smoke plus statistical verification).** The
MATLAB layer covers:

- the shared helpers under `src/common` (initialization, midpoint repair, donor
  selection, RNG setup, population reduction);
- all seven optimizer smoke paths on the pure-MATLAB `sphere` problem
  (`test_dt_gsk_smoke.m` also checks the DT-GSK reference golden values and
  every dimension tier);
- the runner output schema, resume behavior (`test_runner_resume.m`), seed
  schedules, and the unified fair-start `X0` wiring
  (`test_runner_fair_start.m`), and the algorithms.ini aliases
  (`test_algorithm_aliases.m`), and the comparison tools
  (`test_comparison_tools.m`) and the opt-in dynamics trace (`test_dynamics_trace.m`) - 16 MATLAB smoke tests in all;
- the MEX bridge cross-check against the original-MEX ground truth at `0`
  deviation;
- the automatic post-run verification verdict (`verification.json`).

The per-optimizer statistical check is `verification.json`, written by every
`gsk_run` (Mandate 1.1c). Its hard-failure checks catch implementation bugs
rather than optimization quality:

- non-finite statistics;
- on known-optimum suites (cec2017, cec2020, cec2013), a best error below
  `negative_error_floor = -1e-6` (beating the optimum is impossible if the port
  is correct);
- at full protocol only, a mean above `gross_factor = 1e6` times a non-trivial
  (`> 1e-8`) reference mean.

A `reduced_budget` run -- one that used an overridden budget or fewer than 25
runs -- makes the gross-deviation check and the win/tie/loss tally
informational, since a short run is legitimately worse than the published table.

## Latest Verification Commands

Run the C++ ground-truth suites:

```powershell
ctest --test-dir build --output-on-failure
```

Run the MATLAB smoke suite (optimizers, runner, bridge cross-check):

```powershell
matlab -batch "run('gsk_family/src/tests/run_matlab_smoke_tests.m')"
```

Check generated summaries against the imported reference tables. Point
`gsk_validate` at a finished run tree, and use a temporary output root so it
does not touch campaign results:

```powershell
gsk_validate --compare results\_run_all\gsk\cec2017 benchmarks\cec_reference_results
```

Re-run the per-optimizer verdict standalone (it is also produced automatically
inside every `gsk_run`):

```powershell
gsk_validate --verify <run_dir> benchmarks\cec_reference_results
```

(`--reduced` is optional when the run directory has `summary\environment.json`:
the protocol is read from its `runs` / `max_nfes_override`; `--reduced` /
`--full` only override it.)

After a multi-optimizer `unified` campaign, confirm the fair-start contract:
the root `run_all_cec*.m` launchers call
`src/runners/verify_unified_seed_schedule.m`, which asserts that the optimizers
run (GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, DT-GSK) used the **same**
seed on every `(Dim, Function, Run)` key they have in common (present in two or
more schedules). A cell missing for some optimizer (for example a failed eGSK
cell) is reported as a `verify_unified_seed_schedule:missingKeys` warning, not a
failure; only a seed mismatch fails. DT-GSK shares the seeds but, as a
documented exception, samples its own initial population instead of the
runner's `X0`.

Compare a DT-GSK campaign run by run against the imported reference
evidence (MATLAB, Statistics and Machine Learning Toolbox, from the project
root with `scripts` on the path):

```matlab
compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
    'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv')
```

It reports, per `(dimension, function)` cell, Best/Median/Mean on both sides,
order-of-magnitude agreement, the two-sided Wilcoxon rank-sum p-value at
`alpha`, the paired signed-rank p-value when the seeds match, and
Holm-adjusted p-values across cells.

## Current Status

All phases were complete and verified on 2026-06-13; the registry counts below
were refreshed when DT-GSK was added as the seventh optimizer:

- Clean CMake build (WinLibs GCC 16.1, `-std=c++20 -static`); all 12 `ctest`
  suites pass. (A 13th suite, the `gskcec_cli_exit_codes` CLI exit-code test,
  was added later; all 13 now pass.)
- `gsk_list --optimizers` lists all seven optimizers (`dt-gsk` included);
  `--benchmarks` lists all five suites with functions and dimensions;
  `--references` loads 165 files / 1411 rows.
- `gsk_validate --suite <s> --smoke` passes for all five suites (CEC2020 reports
  its 4 source data-gap cells as explicit SKIPs); `--suite cec2013 --against
  saved_vectors` matches at `0` deviation.
- The MEX bridge is built and cross-checked from MATLAB against the original-MEX
  ground truth at `0` deviation (`src/tests/test_mex_bridge.m`).
- The MATLAB smoke suite (`run_matlab_smoke_tests`) was green at that
  snapshot: common helpers, the six optimizers of the time, the runner, and the
  bridge cross-check. It now has 16 tests, adding `test_dt_gsk_smoke.m`,
  `test_runner_resume.m`, `test_runner_fair_start.m`,
  `test_algorithm_aliases.m`, `test_comparison_tools.m` and `test_dynamics_trace.m`.
- **DT-GSK** (added after that snapshot) was validated against its reference
  implementation: a line-by-line port matched the unmodified reference
  implementation on identical random numbers in all four dimension tiers and
  reproduces the reference's golden values to `1e-13`, and the compact
  three-file version shipped here reproduces that port bit for bit. On the
  CEC2017 campaign (D10, D30 and D50 done; D100 still to run), all 87
  functions agree with the imported reference runs (no significant rank-sum
  difference; two differ only in Best). The campaign is recorded in
  [src/optimizers/dt-gsk/README.md](../../src/optimizers/dt-gsk/README.md),
  which holds the complete validation record.
- An end-to-end `gsk_run --config configs/smoke.yml` runs MATLAB GSK on the
  ported CEC2017 benchmark through the bridge, writes the documented
  `summary`/`curves`/`gen_logs` tree, and `gsk_validate --compare` loads it and
  reports win/tie/loss against the imported references.
- The language-contract checks (no source files in other languages, no
  `cec2013.cpp`, no `.m`/`.R`/`.c` under `cec_suite_cpp`) return nothing.

A reduced-budget `gsk_validate --compare` is a consistency and schema check, not
a full-campaign equivalence claim -- see
[Reproducibility -- Bit-Exact Caveats](reproducibility.md#bit-exact-caveats). No
open blockers.

## Remaining Validation Work

The following raise the evidence from exact-port checks and reduced smoke runs
to full statistical campaigns:

- Run full-budget `unified` campaigns where runtime allows, and confirm the
  seed-schedule audit across the whole family.
- Produce statistical equivalence reports for reference-versus-port comparisons
  on the full matrix (the verification verdict is currently per-run and
  reduced-budget aware). `scripts/compare_reference_runs.m` does this run by
  run wherever per-run reference evidence exists; today that is only the DT-GSK
  CEC2017 `evidence/per_run.csv`, so the other DT-GSK suites (and the other
  optimizers) are compared on aggregate tables only.
- Archive the generated validation artifacts (`verification.json`,
  `seed_schedule.csv`, summary CSVs) under a dated release-evidence folder.
- Extend the smoke matrix where a suite is currently runnable on request only
  (cec2013 and cec2013lsgo are validation/extension suites, not part of the
  default GSK matrix).
