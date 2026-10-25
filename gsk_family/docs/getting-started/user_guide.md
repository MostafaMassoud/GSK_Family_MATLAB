# User Guide

> **What this is:** the everyday command reference for the `gsk_family`
> MATLAB + C++ project: install the toolchain, inspect what is available, run an
> experiment, validate the results, and locate every file the runner writes.
> **For:** anyone who has the repository checked out and wants to use it - no
> prior knowledge of the algorithms required.
> **Prerequisites:** Windows with MATLAB R2025b, a C++20 compiler, and CMake;
> the repository checked out. New to the ideas? Read [explainer.md](explainer.md)
> first. Want a guided first run? Use [tutorial.md](tutorial.md). For the
> full copy-paste, per-algorithm command set, see
> [command_reference.md](command_reference.md).
> **After reading:** you will be able to build the tooling, run a smoke
> experiment, run a single benchmark cell, check output against the published
> reference tables, and find every file a run produces.

This project has two halves joined by one bridge. The CEC benchmark suites are
standalone C++20 ports under `benchmarks/`; the seven GSK-family optimizers are
MATLAB under `src/`; the `gskcec_eval` MEX bridge lets the MATLAB optimizers
evaluate the C++ benchmarks.

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
dt-gsk
```

`--references` prints one line per imported reference file plus `files=` /
`rows=` totals (currently `files=165`, `rows=1411`).

The seven registered optimizers (public hyphen-slug ids):

| Id | Name |
|---|---|
| `gsk` | Baseline Gaining-Sharing Knowledge |
| `agsk` | Adaptive GSK (parameter-pool adaptation + population reduction) |
| `apgsk` | GSK with Adaptive Parameters |
| `fdb-agsk` | AGSK with fitness-distance-balance donor selection |
| `atmals-gsk` | GSK with adaptive memory and local search |
| `egsk` | Enhanced GSK |
| `dt-gsk` | Dimension-Tiered GSK (mechanisms switched on by dimension tier; port of the DT-GSK reference implementation) |

DT-GSK differs from the other six in how it is seeded: it always uses the
unified seed with `threefry`, whatever the seed policy, and samples its own
`NP = 5*D` initial population instead of the runner's shared one (see
[command_reference.md](command_reference.md#37-dt-gsk)).

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

The simplest entry point is a root `run_all_cec*.m` launcher. The launchers sit
one level above the project root, next to the `gsk_family\` folder, so run them
from that parent folder. Each one runs, inside a single MATLAB session, every
optimizer listed in its CONFIG block over the functions/dimensions/runs set
there. The committed CONFIG blocks run only `optimizers = {'gsk'}`, and some
use a reduced set (`run_all_cec2011.m` ships `functions = 4:6`,
`run_all_cec2017.m` `dimensions = [10]`, `run_all_cec2020.m`
`dimensions = [5 10]`); edit the CONFIG block for the full suite, other
dimensions, or other optimizers:

```powershell
Set-Location -LiteralPath ".."   # from gsk_family\ to the folder holding the launchers
matlab -batch "run_all_cec2017"
```

The same pattern exists for `run_all_cec2011`, `run_all_cec2013`,
`run_all_cec2013lsgo`, and `run_all_cec2020`. Launchers default to the
**unified** seed policy with the `threefry` generator (the fair cross-family
schedule) and write under `results\_run_all\<optimizer>\<suite>\`.

`optimizers` may also list aliases from `algorithms.ini` (next to the
launchers): a name for an optimizer with its own settings, e.g. `gsk-np50`
with `base = gsk` and `np_init = 50`. Each alias runs the base's code with
those settings into its own folder, next to the original. Then
`run_compare_algorithms.m` (also next to the launchers) draws the
convergence figures and writes the tables and tests for any mix of
optimizers and aliases. See the command reference, "Algorithm aliases", and
[Comparing Algorithms](../research/comparing_algorithms.md).

### (b) The `gsk_run` orchestrator (config or flags)

`build\gsk_run.exe` validates the request against the C++ benchmark factory,
launches MATLAB to run `src/runners/run_experiment.m`, then auto-verifies the
result against the published reference table.

A quick end-to-end smoke run from a saved config:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

`--root .` rebases the config's relative `output_root` and `reference_root`
under the given project root, so a config behaves the same from any working
directory (explicit `--output` / `--reference` flags resolve against the
working directory). `configs\smoke.yml` runs one optimizer on one CEC2017 cell
at a tiny budget.

Or pass flags directly for a single cell:

```powershell
build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 `
    --function 1 --runs 3
```

`--function` and `--dimension` take one integer per flag; repeat the flag for
several values (e.g. `--function 1 --function 3`). Comma lists such as `1,3`
are rejected, as are non-integer values for `--runs`, `--seed`, and
`--max-evaluations`. Native-dimension suites (`cec2011`, `cec2013lsgo`) require
`--dimension 0`. Add `--matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"` if
MATLAB is not on `PATH`, and `--dry-run` to print the exact MATLAB `-batch`
command without running (needs neither MATLAB nor the bridge). The orchestrator
and the shipped configs default to the **reference** seed policy with the
`threefry` generator (the published-table schedule). Every flag maps to a config
field; see [configuration.md](configuration.md) for the full list. A config that
lists several optimizers runs and verifies every one of them even after an
earlier one fails or `DEVIATES`, prints a per-optimizer summary, and exits with
the first nonzero code (1 MATLAB failure, 2 verification error, 3 `DEVIATES` or
no summary).

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
[command_reference.md](command_reference.md) section 3.

During a run the MATLAB Command Window prints one progress line per run, for
example `gsk cec2017 f1 D10 run 1/3: best=... error=... nfes=... (0.4s)`, then
`run_experiment: wrote <output_dir>`. `SKIP <suite> fN Dd: <reason>` lines
appear for unavailable cells. Runs are sequential by default; pass
`'use_parallel',true` (MATLAB) for parfor execution where determinism is not
required.

## Validate results

Every `gsk_run` **automatically** verifies a run against the same optimizer's
imported reference table and writes `summary\verification.json` (or
`verification_1.json`, `verification_2.json`, ... if a verdict already exists).
The verdict is `CONSISTENT` when no hard-failure check fires, or `DEVIATES` when
one does. `gsk_run` exits nonzero on `DEVIATES`; opt out with `--no-verify`. A
direct `run_experiment(...)` call or a root `run_all_cec*.m` launcher writes no
verdict; it only prints a console mean-error comparison table. To get
`verification.json` for such a run, run `gsk_validate --verify` (below) on its
output directory.

To re-check an existing run directory without re-running the optimizer:

```powershell
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results
```

Without `--reduced` / `--full`, `--verify` reads `runs` and `max_nfes_override`
from the run's `summary\environment.json` and applies the same reduced-protocol
rule as `gsk_run` (full protocol when that file is absent), so the flags are
only overrides: `--reduced` for the short-run context, `--full` for the strict
full-protocol context (where the gross-deviation magnitude check becomes a hard
failure). `--verify` also writes the next available `verification*.json` and
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
functions with no imported table for that optimizer/suite/dimension (for example
any optimizer except `dt-gsk` on CEC2013LSGO, optimizers other than
`gsk`/`dt-gsk` on CEC2013, or any optimizer except `agsk` and `dt-gsk` on
CEC2020); for those the gross-deviation check cannot fire. The walk skips
`_overwrite_archive\` and `_archive\` folders below the results root.

`--compare` and the verdict work on per-function means. To compare a whole
campaign run by run against an imported per-run record (today the DT-GSK
CEC2017 evidence), use the MATLAB script `scripts/compare_reference_runs.m`
(Wilcoxon rank-sum per cell with Holm-adjusted p-values; needs the Statistics
and Machine Learning Toolbox); the Command Reference shows the call in
[section 3.7](command_reference.md#37-dt-gsk).

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
| `summary\` | Per-dimension `Function,Best,Median,Mean,Worst,SD` tables, `per_run.csv`, `seed_schedule.csv`, `environment.json`, and, for `gsk_run` or `gsk_validate --verify`, the `verification.json` verdict. |
| `curves\` | One convergence-trace CSV per (function, dimension) cell (the median run). Rendered `graphs\*.png` files are optional and are written only when `write_graphs=true`. |
| `gen_logs\` | Per-checkpoint generation-log CSVs (`CheckpointErrors_*`). |

Re-running an `(optimizer, suite)` with `overwrite=false` preserves the existing
tree: the runner resumes from `summary\per_run.csv`, skips completed run ids
(only when the stored seed, budget and generator still match the active run;
other run ids are re-run and appended), appends missing rows, and archives
refreshed fixed-name artifacts under `_archive\<timestamp>\`.
With `overwrite=true`, the previous active result tree is moved to
`_overwrite_archive\<suite>_<timestamp>\` before a clean replacement tree is
created.

Imported reference evidence stays read-only:

```text
benchmarks\cec_reference_results\
```

The runner refuses to write generated output into this imported reference tree:
the check runs on every run, before anything is created, and raises
`run_experiment:outputUnsafe`. Relative `output_dir` values are resolved against
the current MATLAB folder. For the exact filenames and CSV columns, see
[result_schema.md](../reference/result_schema.md).

## Documentation artifacts

Build the browsable HTML documentation (PowerShell + Pandoc 3.8 or newer, with
a built-in fallback renderer when Pandoc is absent or older, and Doxygen for
the C++ API if present):

```powershell
powershell -File scripts\build_docs.ps1
```

This assembles every Markdown page into a navigable site at
`docs\html\index.html`, with a sidebar, per-page tables of contents, a separate
page per algorithm, diagrams, and the Doxygen C++ API reference. The Markdown
sources are the source of truth; the site is rebuildable at any time. Add
`-Clean` to remove `docs\html` first, or `-Pandoc` / `-Doxygen` to point at
specific executables.
