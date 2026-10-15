# User Guide

> **What this is:** the everyday command reference for the `gsk_family`
> MATLAB + C++ project: install the toolchain, inspect what is available, run an
> experiment, validate the results, and locate every file the runner writes.
> **For:** anyone who has the repository checked out and wants to use it - no
> prior knowledge of the algorithms required.
> **Prerequisites:** Windows with MATLAB R2025b, a C++20 compiler, and CMake;
> the repository checked out. New to the ideas? Read [explainer.md](explainer.md)
> first. Want a guided first run? Use [tutorial.md](tutorial.md). For the
> full copy-paste, per-algorithm command set, see [runbook.md](runbook.md).
> **After reading:** you will be able to build the tooling, run a smoke
> experiment, run a single benchmark cell, check output against the published
> reference tables, and find every file a run produces.

This project has two halves joined by one bridge. The CEC benchmark suites are
standalone C++20 ports under `benchmarks/`; the six GSK-family optimizers are
MATLAB under `src/`; the `gskcec_eval` MEX bridge lets the MATLAB optimizers
evaluate the C++ benchmarks. There is no Python anywhere.

A note on commands: examples use PowerShell, the project's development shell on
Windows. Run them from the project root (the folder that contains
`CMakeLists.txt` and `README.md`) unless told otherwise. Substitute your own
absolute paths for any `C:\path\to\...` placeholder - do not copy one machine's
paths.

## Install

There is nothing to `install` in the package sense; instead you build two
artifacts. Both are written under `build\` and are gitignored.

**1. Build the C++ tooling and run its tests.** This needs only CMake and a
C++20 compiler - no MATLAB. From the project root:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

`-S .` is the source directory (the project root), `-B build` is the build
directory (created for you), and `-j` builds in parallel. `ctest` checks every
benchmark port against fixed ground-truth vectors from the original reference
implementations. A healthy tail is `100% tests passed, 0 tests failed out of
<N>` across the registered test suites. If any test fails, stop - the toolchain
or build is the problem, not your experiment.

If `cmake` / `g++` / `ctest` are not on `PATH`, call them by full path and pass
the compiler explicitly (MATLAB also bundles a usable CMake at
`C:\path\to\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe`):

```powershell
& "C:\path\to\mingw64\bin\cmake.exe" -S . -B build -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"
& "C:\path\to\mingw64\bin\cmake.exe" --build build -j
& "C:\path\to\mingw64\bin\ctest.exe" --test-dir build --output-on-failure
```

**2. Build the MEX bridge.** Every MATLAB CEC run evaluates the C++ benchmarks
through `gskcec_eval`, so this step is **required before any MATLAB CEC run**. It
needs MATLAB plus the same MinGW toolchain (it compiles the benchmark sources
directly and does not need the MATLAB `mex` command or a prior CMake build):

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This produces `build\mex\gskcec_eval.mexw64`. If MATLAB or `g++` are not
auto-detected, pass them explicitly:

```powershell
powershell -File scripts\build_mex_bridge.ps1 `
    -MatlabRoot "C:\path\to\MATLAB\R2025b" `
    -Gxx "C:\path\to\mingw64\bin\g++.exe"
```

The runner adds `build\mex` to the MATLAB path automatically. Only the
pure-MATLAB `sphere` smoke tests run without the bridge. Rebuild the bridge after
changes to CEC suite source files or
`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/` - `cmake --build build -j`
refreshes the CLIs but **not** the bridge, since they are separate binaries.

For MATLAB to be found by the C++ orchestrator, put `...\bin` on `PATH`, set
`$env:GSKCEC_MATLAB`, or pass `--matlab <exe>` per call (see
[Run an experiment](#run-an-experiment)).

## Inspect available assets

Before running anything, list what the tooling offers - benchmark suites,
optimizers, and how many imported reference tables are present. These commands
need only the C++ build, not MATLAB:

```powershell
build\gsk_list.exe --benchmarks
build\gsk_list.exe --optimizers
build\gsk_list.exe --references benchmarks\cec_reference_results
```

What you will see (shape, not exact counts):

```text
cec2011  functions=1,2,...,22  dimensions=native-per-function
cec2013  functions=1,2,...,28  dimensions=2,5,10,20,30,40,50,60,70,80,90,100
cec2013lsgo  functions=1,2,...,15  dimensions=native-per-function
cec2017  functions=1,2,...,30  dimensions=10,30,50,100
cec2020  functions=1,2,...,10  dimensions=5,10,15,20
```

```text
gsk
agsk
apgsk
atmals-gsk
egsk
fdb-agsk
```

`--references` prints one line per imported reference file plus `files=` /
`rows=` totals.

The six registered optimizers (public hyphen-slug ids):

| Id | Name |
|---|---|
| `gsk` | Baseline Gaining-Sharing Knowledge |
| `agsk` | Adaptive GSK (parameter-pool adaptation + population reduction) |
| `apgsk` | GSK with Adaptive Parameters |
| `fdb-agsk` | AGSK with fitness-distance-balance donor selection |
| `atmals-gsk` | GSK with adaptive memory and local search |
| `egsk` | Enhanced GSK |

The five benchmark suites are `cec2017`, `cec2011`, `cec2020`, `cec2013`, and
`cec2013lsgo`. See [benchmark_protocol.md](../reference/benchmark_protocol.md)
for each suite's dimensions, function counts, and evaluation budgets.

You can also smoke-test that a suite constructs and evaluates to finite numbers
(still no MATLAB, no optimizer):

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
```

CEC2020 prints explicit `SKIP ...` lines for the few (function, dimension) cells
without reference data; that is expected, not a failure.

## Run an experiment

There are three ways to run, all producing the same result files. Use whichever
fits the moment.

### (a) Root launchers (whole-suite campaigns)

The simplest entry point is a root `run_all_cec*.m` launcher, run from the
project root. Each drives one MATLAB invocation per optimizer over its suite's
default matrix:

```powershell
matlab -batch "run_all_cec2017"
```

The same pattern exists for `run_all_cec2011`, `run_all_cec2013`,
`run_all_cec2013lsgo`, and `run_all_cec2020`. Launchers default to the
**unified** seed policy with the `threefry` generator (the fair cross-family
schedule) and write under `results\_run_all\<optimizer>\<suite>\`.

### (b) The `gsk_run` orchestrator (config or flags)

`build\gsk_run.exe` validates the request against the C++ benchmark factory,
launches MATLAB to run `src/runners/run_experiment.m`, then auto-verifies the
result against the published reference table.

A quick end-to-end smoke run from a saved config:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

`--root .` rewrites the config's relative `output_root`, `reference_root`, and
`data_root` under the current project root, so a config moves between machines
cleanly. `configs\smoke.yml` runs one optimizer on one CEC2017 cell at a tiny
budget.

Or pass flags directly for a single cell:

```powershell
build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 `
    --function 1 --runs 3
```

`--function` and `--dimension` accept a single value, a repeated flag, or
several values. Native-dimension suites (`cec2011`, `cec2013lsgo`) require
`--dimension 0`. Add `--matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"` if
MATLAB is not on `PATH`, and `--dry-run` to print the exact MATLAB `-batch`
command without running (needs neither MATLAB nor the bridge). The orchestrator
and the shipped configs default to the **reference** seed policy with the
`threefry` generator (the published-table schedule). Every flag maps to a config
field; see [configuration.md](configuration.md) for the full list.

### (c) MATLAB direct (`run_experiment`)

From the MATLAB IDE you can call the runner directly. This is handy for
step-through debugging and exposes the same knobs as the config:

```matlab
cd('<root>/src/runners')
run_experiment('optimizer','gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',3, 'base_seed',20240620, ...
    'max_nfes',0, ...   % 0 = suite default budget = 10000*D
    'project_root','<root>', ...
    'output_dir','<root>/results/gsk/cec2017')
```

Direct `run_experiment` defaults to the **unified** seed policy. For full
per-optimizer control - population size, `kf`/`kr`/`k`/`p`, `fdb_case`,
`protocol`, `use_fmincon`, or a custom single seed - use the lower-level path
(`gskcec_make_problem` + `<name>_optimize(problem, options)`) documented in
[runbook.md](runbook.md) section 3.

During a run the MATLAB Command Window prints one progress line per run, for
example `gsk cec2017 f1 D10 run 1/3: best=... error=... nfes=... (0.4s)`, then
`run_experiment: wrote <output_dir>`. `SKIP <suite> fN Dd: <reason>` lines
appear for unavailable cells. Runs are sequential by default; pass
`'use_parallel',true` (MATLAB) for parfor execution where determinism is not
required.

## Validate results

Every `gsk_run` (and `run_experiment`) **automatically** verifies a run against
the same optimizer's imported reference table and writes
`summary\verification.json` (or `verification_1.json`, `verification_2.json`,
... if a verdict already exists). The verdict is `CONSISTENT` when no
hard-failure check fires, or `DEVIATES` when one does. `gsk_run` exits nonzero on
`DEVIATES`; opt out with `--no-verify`.

To re-check an existing run directory without re-running the optimizer:

```powershell
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results --reduced
```

Use `--reduced` for a short or budget-overridden run and `--full` to apply the
strict full-protocol context (where the gross-deviation magnitude check becomes a
hard failure). `--verify` also writes the next available `verification*.json` and
exits nonzero on `DEVIATES`.

To see the numbers side by side against the published tables across the whole
results tree:

```powershell
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

What you will see:

```text
gsk cec2017 f1 D10 mean=<your mean> ref_mean=<published mean> rel_diff=<...> -> <win|tie|loss>
...
compared=<N> win=<...> tie=<...> loss=<...> no_reference=<...>
```

Lower mean is better; a `tie` is within relative `1e-8`; `no_reference` counts
functions with no published table for that optimizer/suite (for example
`apgsk`/`egsk`/`fdb-agsk` on CEC2011, or anything on CEC2013/LSGO), where the
verdict is still `CONSISTENT`.

**Reduced-budget runs will not reproduce full-budget reference statistics.** A
tiny smoke run is legitimately worse than the published full-budget table, so
read its comparison as a consistency and schema check, not a paper-quality
benchmark claim. The verdict, thresholds, and comparison rules are documented in
[result_schema.md](../reference/result_schema.md) and
[benchmark_protocol.md](../reference/benchmark_protocol.md).

## Output locations

Generated results are written in the CEC-competition layout, one tree per
`(optimizer, suite)`:

```text
results\<optimizer>\<suite>\
  summary\
  curves\
  gen_logs\
```

(The root `run_all_cec*.m` launchers write under
`results\_run_all\<optimizer>\<suite>\` instead.)

| Folder | Holds |
|---|---|
| `summary\` | Per-dimension `Function,Best,Median,Mean,Worst,SD` tables, `per_run.csv`, `seed_schedule.csv`, `environment.json`, and the `verification.json` verdict. |
| `curves\` | One convergence-trace CSV per (function, dimension) cell (the median run). Rendered `graphs\*.png` files are optional and are written only when `write_graphs=true`. |
| `gen_logs\` | Per-checkpoint generation-log CSVs (`CheckpointErrors_*`). |

Re-running an `(optimizer, suite)` with `overwrite=false` preserves the existing
tree: the runner resumes from `summary\per_run.csv`, skips completed run ids
(only when the stored seed still matches the active policy), appends missing
rows, and archives refreshed fixed-name artifacts under `_archive\<timestamp>\`.
With `overwrite=true`, the previous active result tree is moved to
`_overwrite_archive\<suite>_<timestamp>\` before a clean replacement tree is
created.

Imported reference evidence stays read-only:

```text
benchmarks\cec_reference_results\
```

The runner refuses to write generated output into this imported reference tree.
For the exact filenames and CSV columns, see
[result_schema.md](../reference/result_schema.md).

## Documentation artifacts

Build the browsable HTML documentation (PowerShell + Pandoc, with Doxygen for
the C++ API if present - no Python):

```powershell
powershell -File scripts\build_docs.ps1
```

This assembles every Markdown page into a navigable site at
`docs\html\index.html`, with a sidebar, per-page tables of contents, a separate
page per algorithm, diagrams, and the Doxygen C++ API reference. The Markdown
sources are the source of truth; the site is rebuildable at any time. Add
`-Clean` to remove `docs\html` first, or `-Pandoc` / `-Doxygen` to point at
specific executables.
