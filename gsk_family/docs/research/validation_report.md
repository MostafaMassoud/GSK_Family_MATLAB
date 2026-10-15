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
standalone C++20 with no MATLAB, R, MEX, or Python at benchmark runtime. The
`ctest` suite covers:

- the core library and RNG;
- imported reference-table loading (35 files / 894 rows, including `N/A` cells);
- CEC2017 against 600 ground-truth rows (rel-tol `1e-10`, max deviation
  about `4.8e-15`);
- CEC2020 against 180 rows (max deviation about `2.8e-16`);
- CEC2013 against analytic checks, optimum-at-shift, and a self-generated
  regression baseline at `1e-12`;
- CEC2013LSGO against side-by-side reference agreement at the probe points;
- CEC2011 work packages A/B/C plus integration;
- the experiment-comparison code;
- a `gsk_bench` smoke run so the timing harness cannot rot.

**MATLAB optimizers and runner (smoke plus statistical verification).** The
MATLAB layer covers:

- the shared helpers under `src/common` (initialization, midpoint repair, donor
  selection, RNG setup, population reduction);
- all six optimizer smoke paths on the pure-MATLAB `sphere` problem;
- the runner output schema, resume behavior, and seed schedules;
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
gsk_validate --verify <run_dir> benchmarks\cec_reference_results --reduced
```

After a multi-optimizer `unified` campaign, confirm the fair-start contract:
the root `run_all_cec*.m` launchers call
`src/runners/verify_unified_seed_schedule.m`, which asserts that GSK, AGSK,
APGSK, ATMALS-GSK, eGSK, and FDB-AGSK all used the **same** seed for every
`(Dim, Function, Run)` cell.

## Current Status

All phases were complete and verified on 2026-06-13:

- Clean CMake build (WinLibs GCC 16.1, `-std=c++20 -static`); all 12 `ctest`
  suites pass.
- `gsk_list --optimizers` lists all six optimizers; `--benchmarks` lists all
  five suites with functions and dimensions; `--references` loads 35 files /
  894 rows.
- `gsk_validate --suite <s> --smoke` passes for all five suites (CEC2020 reports
  its 4 source data-gap cells as explicit SKIPs); `--suite cec2013 --against
  saved_vectors` matches at `0` deviation.
- The MEX bridge is built and cross-checked from MATLAB against the original-MEX
  ground truth at `0` deviation (`src/tests/test_mex_bridge.m`).
- The MATLAB smoke suite (`run_matlab_smoke_tests`) is green: common helpers,
  all six optimizers, the runner, and the bridge cross-check.
- An end-to-end `gsk_run --config configs/smoke.yml` runs MATLAB GSK on the
  ported CEC2017 benchmark through the bridge, writes the documented
  `summary`/`curves`/`gen_logs` tree, and `gsk_validate --compare` loads it and
  reports win/tie/loss against the imported references.
- The language-contract checks (no `.py`/`.pyx`, no `cec2013.cpp`, no
  `.m`/`.R`/`.c` under `cec_suite_cpp`) return nothing.

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
  reduced-budget aware).
- Archive the generated validation artifacts (`verification.json`,
  `seed_schedule.csv`, summary CSVs) under a dated release-evidence folder.
- Extend the smoke matrix where a suite is currently runnable on request only
  (cec2013 and cec2013lsgo are validation/extension suites, not part of the
  default GSK matrix).
