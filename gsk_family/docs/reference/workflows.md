# Workflows

> **What this is:** the main paths data takes through the project - running a
> campaign from the C++ CLI, running optimizers from MATLAB (a launcher or a
> direct `run_experiment` call), validating output, spreading runs across cores,
> and rebuilding the docs. **For:** anyone who wants the big-picture flow before
> diving into a specific module. **Prerequisites:** a built toolchain plus the
> MEX bridge (see the [Runbook](../../../RUNBOOK.md))
> and the terms in [glossary.md](glossary.md). **After reading** you will know
> which entry point to use for which job and have one worked end-to-end example.

This document describes the main execution paths through the project. Each path
is sketched as a numbered flow; read the arrows top to bottom. For the
symbol-level contracts see [matlab_interface.md](matlab_interface.md); for the
files produced see [result_schema.md](result_schema.md).

There are three ways to start a run, all of which end in the same result tree:

- **C++ CLI** - `build\gsk_run.exe` (a config or explicit flags); it validates,
  drives MATLAB, then auto-verifies. Default `seed_policy=reference`.
- **MATLAB launcher** - `run_all_cec*.m` (edit a CONFIG block, press Run).
  Default `seed_policy=unified`.
- **MATLAB direct** - call `run_experiment(...)` yourself. Default
  `seed_policy=unified`.

## CLI Experiment Workflow

The everyday terminal path: `gsk_run.exe` turns a request (a strict YAML config
or direct flags) into a fixed, reproducible set of runs and writes the full
result tree, then verifies it.

```text
gsk_run.exe --config configs\smoke.yml --root .
  -> parse the strict flat-YAML config OR the direct CLI flags   (single C++ parser)
  -> validate the request against the benchmark factory          (is F/D part of the suite?)
  -> locate MATLAB                                                (--matlab, GSKCEC_MATLAB, then PATH)
  -> build one MATLAB "-batch" call PER optimizer                 (cd src/runners; run_experiment(...))
  -> [MATLAB] run_experiment: resolve cells, fix the seed schedule,
              evaluate the C++ benchmark via the gskcec_eval MEX bridge,
              write per_run rows, summaries, curves, gen_logs, environment.json
  -> auto-compare the run with the same optimizer's reference table
  -> write summary\verification.json  (CONSISTENT / DEVIATES; exit nonzero on DEVIATES)
```

The same path serves smoke tests and full campaigns; only the budget and run
count differ. The CLI never runs an optimizer itself and never parses results
math - it orchestrates MATLAB and then calls the C++ comparison
(the header comment of `benchmarks/cec_suite_cpp/cec_tools/src/cli/gsk_run.cpp`).
The output root is `out_root / optimizer / suite` (`run_one` in `gsk_run.cpp`). A
config that lists several optimizers runs and verifies every one of them even
after an earlier one fails or `DEVIATES`, prints a per-optimizer summary, and
exits with the first nonzero code. The accepted config keys and
flag names are in the Command Reference's knob-mapping table
([../getting-started/command_reference.md](../getting-started/command_reference.md)).

Preview without running (needs neither MATLAB nor the bridge):

```powershell
build\gsk_run.exe --config configs\smoke.yml --root . --dry-run
```

This prints the exact MATLAB `-batch` command, which is the clearest view of how
the C++ orchestrator hands the request to the MATLAB runner.

## MATLAB Workflow

The two MATLAB paths write the same files as the CLI but skip the C++
orchestrator. Use them from the MATLAB IDE.

**Launcher (`run_all_cec*.m`).** One file per suite, sitting next to the
`gsk_family/` folder. Edit the CONFIG block (optimizer list, functions,
dimensions, runs, budget, seed policy, parallel flag), then press Run.

```matlab
% Edit the CONFIG block at the top of run_all_cec2017.m, then Run.
% It loops over the optimizer list and calls run_experiment(...) for each.
% Full-suite settings shown; the committed CONFIG ships optimizers = {'gsk'}
% and dimensions = [10].
optimizers = {'gsk', 'agsk', 'apgsk', 'atmals-gsk', 'egsk', 'fdb-agsk', 'dt-gsk'};
functions  = 1:30;     % F2 is auto-excluded -> 29 functions
dimensions = [10 30 50 100];
runs       = 51;
seed_policy = 'unified';   % fair cross-family default for new experiments
use_parallel = true;
```

The launcher checks the MEX prerequisite up front
(`gskcec_require_mex(root, ...)`), runs each optimizer through
`run_experiment(...)`, writes under `gsk_family/results/_run_all/<opt>/<suite>/`,
and - under unified policy - cross-checks that the optimizers that completed used
the same seed per `(D,function,run)` via `verify_unified_seed_schedule(...)`
(called at the end of `run_all_cec2017.m`). Seeds are compared on every key
present in two or more schedules; a key missing from an optimizer (failed or
skipped cells, or a different functions/runs configuration) is only a
`verify_unified_seed_schedule:missingKeys` warning, and only a seed mismatch
fails.

DT-GSK (`'dt-gsk'` in the list) is unified-only - the unified seed and
`threefry` under any `seed_policy` - so its schedule passes the same
cross-check, but it draws its own `NP = 5*D` first population instead of the
runner's `X0` (see [seed_policy.md](seed_policy.md)).

**Direct (`run_experiment`).** Call the runner yourself for one optimizer with
full argument control. This is the high-level path; for custom variant
parameters (population, `kf`, `fdb_case`, ...) or a custom single seed, use the
lower-level `gskcec_make_problem` + `<opt>_optimize` path shown in the Command Reference.

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',3, 'base_seed',20240620, ...
    'max_nfes',0, ...   % 0 = suite default = 10000*D
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/gsk/cec2017')
```

A direct `run_experiment(...)` call defaults to `seed_policy='unified'` and
`use_parallel=false` (the inputParser defaults for `'seed_policy'` /
`'use_parallel'` in `src/runners/run_experiment.m`). It does **not** run the
C++ post-run verification step - that is performed by `gsk_run.exe` or, on
demand, by `gsk_validate.exe --verify` (see below). The argument-to-knob mapping
(functions, dimensions, budget, runs, seed, policy) is the same table the CLI
flags map to; see the Command Reference.

## Worked End-to-End Example

This runs a small but complete campaign through the CLI, then validates it - the
same two commands a reviewer would use, just with a reduced budget so it finishes
in seconds. (Prerequisite: the C++ build and the one-time MEX bridge build; see
[../getting-started/tutorial.md](../getting-started/tutorial.md).)

```powershell
# 1. Run: gsk on cec2017, functions 1 and 3, D=10, 3 runs, reduced budget.
build\gsk_run.exe --optimizer gsk --suite cec2017 --function 1 --function 3 `
    --dimension 10 --runs 3 --max-evaluations 2000

# 2. Inspect the tree that was written.
#    results\gsk\cec2017\summary\  curves\  gen_logs\

# 3. Re-check the run's verdict against the bundled references (the protocol is
#    read from the run's summary\environment.json; --reduced/--full override it).
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results
```

What happens, step by step:

1. `gsk_run.exe` validates the request against the C++ benchmark factory, then
   builds one `-batch` MATLAB call that runs `src/runners/run_experiment.m` for
   `gsk` on the cells `(F1, D10)` and `(F3, D10)`.
2. Because `gsk_run` defaults to `seed_policy='reference'`, GSK seeds with
   `twister` and per-run seed `base_seed + 9973*func + run-1`. (Pass
   `--seed-policy unified` to share one optimizer-independent seed and a
   runner-generated fair-start `X0` instead. `--optimizer dt-gsk` gets the
   unified seed and `threefry` under either policy.)
3. `run_experiment` evaluates the ported C++ CEC2017 functions through the
   `gskcec_eval` MEX bridge and writes `per_run.csv`, the per-dimension summary
   CSV, `seed_schedule.csv`, the median-run curves, the checkpoint `gen_logs`,
   and `environment.json`.
4. `gsk_run` then auto-compares the run with the `gsk` reference table and writes
   `summary\verification.json`. Step 3 above re-runs that verdict on the existing
   tree without re-running the optimizer.

Because `--max-evaluations` is set (and runs `< 25`), the run is flagged
**reduced budget**, so the gross-deviation check and the win/tie/loss tally are
informational - a 2000-evaluation run is legitimately worse than the full
`10000*D` published table, and that is not a bug. Drop `--max-evaluations` and
raise `--runs` for a full campaign. The reduced-budget rows are **not** reused
then: every run id is re-run at the full budget and appended, the old rows stay
in `per_run.csv` as history, and the summary uses only the full-budget runs
(resume matches seed, budget and generator). Cells not requested in a resumed
session keep their previous summary rows (add mode), so use a fresh output
directory or `--overwrite` for a clean full-protocol tree. The artifacts are
detailed in [result_schema.md](result_schema.md).

## Validation Workflow

There are two distinct senses of "correct", checked by different tools:

- **Benchmark *ports*** are checked **exactly** against fixed-vector ground truth
  by the C++ unit tests (`ctest --test-dir build --output-on-failure`) and the
  smoke / saved-vector checks of `gsk_validate`. No optimizer is involved.
- **Optimizer *results*** are checked **statistically** against the same
  optimizer's published table by the comparison in
  `benchmarks/cec_suite_cpp/cec_tools/src/experiment/comparison.cpp`.

Port health checks (no MATLAB needed):

```powershell
build\gsk_validate.exe --suite cec2017 --smoke               # construct+evaluate every (F,D) cell
build\gsk_validate.exe --suite cec2013 --against saved_vectors
```

Result comparison and verdict:

```text
gsk_validate --verify <run_dir> <reference_root> [--reduced|--full]
  -> load the run's per-dimension summary CSVs; take optimizer, suite and
     dimension from each file name <opt>_<suite>_D<dim>.csv (not the folders)
  -> protocol: --reduced/--full if given, else runs/max_nfes_override from
     summary\environment.json (full protocol when absent)
  -> find the matching reference table (the optimizer slug is the reference
     folder name; no alias mapping)
  -> compare function-level summary means, each row under its own suite's rules
     and against its own reference row
  -> write summary\verification.json beside the run (verification_1.json, ... on rerun)
  -> print verdict / win-tie-loss / hard_failures   (exit nonzero on DEVIATES)
```

The verdict is `CONSISTENT` unless a **hard-failure** check fires (non-finite
statistics; for known-optimum suites a best error below the negative floor, since
beating the optimum is impossible if correct; or, at full protocol only, a mean
grossly above a non-trivial reference mean), in which case it is `DEVIATES`
(`classify_run` in `comparison.cpp`). A reduced protocol (short/over-budget run)
makes the gross-deviation check informational; `--full` makes it a hard failure.
For a side-by-side numbers table across the whole results tree (archive folders
`_overwrite_archive/` and `_archive/` below the results root are skipped):

```powershell
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

When no reference table exists for an (optimizer, suite[, dimension]) pairing,
win/tie/loss are `0`, `missing_reference` counts the unmatched functions, and
the gross-deviation check cannot fire (the finiteness and sign checks still
apply). The verdict fields and thresholds are explained in
[result_schema.md](result_schema.md).

Per-run statistical comparison (MATLAB, Statistics and Machine Learning
Toolbox). Where per-run reference evidence exists, as for DT-GSK on CEC2017,
`scripts/compare_reference_runs.m` compares two `per_run.csv` sets cell by cell:

```text
compare_reference_runs(generated, reference, ['alpha',0.05, 'out','comparison.csv'])
  -> per (dimension, function): Best / Median / Mean of each set
  -> both sides rounded to 'sig_digits' (11) significant digits first
  -> magnitude check: Best, Median and Mean agree within 'decades' orders of magnitude
  -> two-sided Wilcoxon rank-sum (ranksum) at alpha; paired signed-rank when the
     seeds match (informational)
  -> MATCH / DIFFERS per cell; Holm-adjusted rank-sum p-values across cells
```

```matlab
compare_reference_runs('results/_run_all/dt-gsk/cec2017', ...
    'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv')
```

## Parallel Workflow

The execution path: how independent runs are spread across cores
deterministically.

`run_experiment` runs each `(function, run)` task in a `parfor` loop when
`use_parallel` is true (the parfor run loop in `src/runners/run_experiment.m`).
`run_all_cec2011.m` and `run_all_cec2017.m` ship `use_parallel = true`, while
`run_all_cec2013.m`, `run_all_cec2013lsgo.m` and `run_all_cec2020.m` ship
`use_parallel = false` (the serial baseline); `gsk_run` and a direct
`run_experiment(...)` call default to serial. Set it to true only after a worker
smoke test (see [seed_policy.md](seed_policy.md)). When parallel is requested,
the runner first ensures a **process-based** pool backs the loop
(`ensure_process_pool()` in `run_experiment.m`). If the Parallel Computing
Toolbox or a pool is unavailable, the `parfor` degrades to a serial loop and the
run is still correct (same function).

Parallel and serial produce **bit-identical** artifacts. The reason is that
determinism does not depend on iteration order: each `(D,function,run)` cell has
its own seed from `get_cec_seed(...)`, and under unified mode the runner draws
the fair-start `X0` and captures the post-initialization RNG state outside the
optimizer, then hands both in (`make_unified_initial_population(...)` in
`run_experiment.m`). Every task therefore receives the same payload - same
seed, same first population, same next-draw stream position - regardless of which
worker executes it or in what order. DT-GSK's payload is the seed alone: its
first population and every later draw come from Threefry substreams derived
from that seed, so it is equally order-independent. The chosen policy and population source are
recorded in `environment.json` (`use_parallel`, `initial_population_policy`). See
[seed_policy.md](seed_policy.md) for the full seed contract.

## Documentation Workflow

Documentation is maintained as Markdown under `docs/` - that is the source of
truth. The browsable HTML site is
built by a PowerShell script that renders the tracked Markdown (via Pandoc, with
a built-in minimal fallback when Pandoc is absent or older than 3.8), generates
the C++ API
reference with Doxygen when present, and renders Mermaid diagrams client-side.

```text
scripts\build_docs.ps1
  -> render every tracked docs\**\*.md page to flat HTML under docs\html\
  -> (if doxygen present) generate + link the C++ API reference
  -> (mermaid.js) render diagrams client-side
```

Rebuild after editing any documentation Markdown so the generated HTML under
`docs/html/` stays in sync:

```powershell
powershell -File scripts\build_docs.ps1
```

Use `-Clean` to remove `docs/html` first, and `-Pandoc` / `-Doxygen` to point at
those tools explicitly if they are not on PATH (the parameter list in the
header of `scripts/build_docs.ps1`).
