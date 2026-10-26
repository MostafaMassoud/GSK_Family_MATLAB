# Command Reference

> **What this is:** the full copy-paste command reference for every algorithm,
> for both the MATLAB IDE and a Windows terminal - build the tooling and run
> **every** optimizer (`gsk`, `agsk`, `apgsk`, `atmals-gsk`, `egsk`,
> `fdb-agsk`, `dt-gsk`) on every supported CEC suite, then verify and compare
> against the published reference tables. **For:** anyone running real
> experiments who wants exact, per-algorithm commands. **Prerequisites:** the
> build and MEX bridge (sections 2.4-2.5), MATLAB R2025b for any optimizer run;
> new to the project? Start with [RUNBOOK.md](../../../RUNBOOK.md), then
> [tutorial.md](tutorial.md). **After reading:** you will be able to run, resume,
> verify, and compare any optimizer/suite combination.

A complete, copy-paste command reference for the `gsk_family` project: how to build the
tooling and run **every** optimizer (`gsk`, `agsk`, `apgsk`, `atmals-gsk`,
`egsk`, `fdb-agsk`, `dt-gsk`) on every supported CEC suite, from both the MATLAB IDE and a
Windows terminal, then verify and compare the results against the published
reference tables. Every command below was checked against the actual sources
(`benchmarks/cec_suite_cpp/cec_tools/src/cli/*.cpp`, `src/runners/run_experiment.m`,
`src/runners/gskcec_make_problem.m`, the `configs/*.yml`, and each
`src/optimizers/<name>/*`).

> Throughout, `<root>` (or "project root") is the folder that contains
> `CMakeLists.txt` and `README.md` — i.e.
> `<repo>\gsk_family`. Substitute your
> own absolute paths for the `C:\path\to\...` placeholders; do not copy any one
> machine's paths. Commands are shown for **PowerShell** (the project's
> development platform); run them from the project root unless told otherwise.

## Table of contents

- [1. Summary](#1-summary)
- [2. Common setup](#2-common-setup)
  - [2.1 Prerequisites & environment](#21-prerequisites--environment)
  - [2.2 Required folders & files](#22-required-folders--files)
  - [2.3 MATLAB version, toolboxes & fallbacks](#23-matlab-version-toolboxes--fallbacks)
  - [2.4 Build the C++ CLIs (cmake / ctest)](#24-build-the-c-clis-cmake--ctest)
  - [2.5 Build the MEX bridge](#25-build-the-mex-bridge)
  - [2.6 Putting MATLAB on PATH / passing --matlab](#26-putting-matlab-on-path--passing---matlab)
  - [2.7 Setting functions, dimensions, population, budget, runs, seed](#27-setting-functions-dimensions-population-budget-runs-seed)
  - [2.8 Suites, dimensions & default budgets (reference)](#28-suites-dimensions--default-budgets-reference)
  - [2.9 Where results land](#29-where-results-land)
- [3. Per-algorithm run guides](#3-per-algorithm-run-guides)
  - [3.1 gsk](#31-gsk)
  - [3.2 agsk](#32-agsk)
  - [3.3 apgsk](#33-apgsk)
  - [3.4 atmals-gsk](#34-atmals-gsk)
  - [3.5 egsk](#35-egsk)
  - [3.6 fdb-agsk](#36-fdb-agsk)
  - [3.7 dt-gsk](#37-dt-gsk)
- [4. Reproduce the default matrix](#4-reproduce-the-default-matrix)
- [5. Troubleshooting appendix](#5-troubleshooting-appendix)
- [6. Quick command reference](#6-quick-command-reference)

---

## 1. Summary

This project has two halves. The **CEC benchmark suites** (CEC2011, CEC2013,
CEC2013LSGO, CEC2017, CEC2020) are standalone C++20 ports under `benchmarks/`;
the **seven GSK-family optimizers** are MATLAB under `src/optimizers/`. A small
C++ orchestrator (`gsk_run`) drives MATLAB's `run_experiment.m`, which evaluates
the C++ benchmarks through the `gskcec_eval` MEX bridge, writes results in the
CEC-competition layout, and auto-verifies each run against the published
reference table (`CONSISTENT` / `DEVIATES`).

You can run an algorithm two independent ways: **(A)** straight from the MATLAB
IDE (`run_experiment(...)`, or the lower-level `gskcec_make_problem` +
`<name>_optimize(problem, options)` for full per-optimizer control), or **(B)**
from a Windows terminal with `build\gsk_run.exe` (via a `--config` file or
explicit flags). Both paths produce the same result files; the terminal path
additionally prints the verification verdict.

---

## 2. Common setup

Everything in this section is shared by all seven algorithms. Each algorithm
section below refers back here for the shared steps and only adds its own
options, suites, and quirks.

### 2.1 Prerequisites & environment

| Tool | Needed for | Version |
|---|---|---|
| **CMake** | configuring/building the C++ tooling | ≥ 3.20 |
| **A C++20 compiler** | compiling the benchmarks, library, CLIs, tests, and the MEX bridge | developed with WinLibs MinGW-w64 GCC 16.x |
| **MATLAB** | running the GSK optimizers and building the MEX bridge | R2025b used by the project |

Two practical ways to get the C++ toolchain:

- Install **WinLibs MinGW-w64** (bundles `g++`; 4.x also bundles `cmake`). The
  project was built with the winget package
  `BrechtSanders.WinLibs.POSIX.UCRT`; its binaries land under
  `%LOCALAPPDATA%\Microsoft\WinGet\Packages\...\mingw64\bin`.
- Or reuse the **CMake that ships inside MATLAB**, at
  `<matlabroot>\bin\win64\cmake\bin\cmake.exe` (for example
  `C:\Program Files\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe`).

Check what is on your PATH:

```powershell
(Get-Command cmake).Source
(Get-Command g++).Source
(Get-Command matlab).Source   # only needed for MATLAB / MEX steps
```

If a tool is **not** on PATH, call it by full path instead (examples are given
throughout), e.g. `& "C:\path\to\mingw64\bin\cmake.exe" ...` and pass the
compiler explicitly with `-DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"`.

> **What needs what.** The C++ build and the C++ tests/validation (sections 2.4,
> and `gsk_list` / `gsk_validate --smoke`) need only CMake + a C++20 compiler —
> **no MATLAB**. Actually *running an optimizer* (any algorithm section, path A
> or B) additionally needs MATLAB and the one-time MEX bridge (section 2.5). The
> pure-MATLAB `sphere` test suite needs no MEX bridge.

### 2.2 Required folders & files

These already exist in the repository; confirm they are present before running:

```text
<root>\CMakeLists.txt                     C++ build entry point
<root>\benchmarks\cec_suite_cpp\<suite>\input_data\   per-suite benchmark data (rotation/shift/shuffle)
<root>\benchmarks\cec_reference_results\         imported reference tables + curated curves/logs (read-only)
<root>\configs\*.yml                      ready-made experiment configs
<root>\src\runners\run_experiment.m       the MATLAB experiment driver
<root>\src\optimizers\<name>\<name>_optimize.m   the seven optimizers
<root>\scripts\build_mex_bridge.ps1       MEX bridge builder
```

Two trees are produced by the build and are gitignored:

```text
<root>\build\gsk_run.exe  gsk_validate.exe  gsk_list.exe   (section 2.4)
<root>\build\mex\gskcec_eval.mexw64                         (section 2.5)
```

Outputs are written under `<root>\results\` (section 2.9). The imported
reference tables and curated benchmark-side convergence assets under
`benchmarks\cec_reference_results` are **never** written to by normal runs.

### 2.3 MATLAB version, toolboxes & fallbacks

- **MATLAB R2025b** is the project version. The optimizers and runner are plain
  MATLAB; no toolbox is strictly required to run `gsk`, `agsk`, `apgsk`,
  `atmals-gsk`, `fdb-agsk`, or `dt-gsk`.
- **eGSK** uses the **Optimization Toolbox** (`fmincon`, SQP) for its IP local
  refinement. Reference-mode eGSK requires `fmincon`; if it is absent, the
  default call raises `egsk:fminconUnavailable`. `options.use_fmincon=false`
  is available only for explicit non-reference diagnostic runs. See
  [3.5 egsk](#35-egsk).
- **ATMALS-GSK** would otherwise need the Fuzzy Logic Toolbox `gaussmf`; the
  port replaces it with a local, mathematically identical helper
  (`atmals_gaussmf.m`), so **no toolbox is needed**.
- The statistics/figures script `scripts/analyze_results.m` is **toolbox-free**
  (Friedman via base `gammainc`, Wilcoxon via base `erfc`, tie ranks via a
  local helper; figures via `boxchart`/`exportgraphics`).
- The per-run campaign comparison `scripts/compare_reference_runs.m` (see
  [3.7](#37-dt-gsk)) **needs the Statistics and Machine Learning Toolbox**
  (`ranksum`, `signrank`); without it, it stops with
  `compare_reference_runs:toolbox`.

### 2.4 Build the C++ CLIs (cmake / ctest)

From the project root, with the WinLibs toolchain on PATH:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

- `-S .` = source dir (project root), `-B build` = build dir (created for you),
  `-j` = parallel build.
- `ctest` validates every benchmark **port** against fixed ground-truth vectors
  from the original reference implementations. A healthy tail is
  `100% tests passed, 0 tests failed out of <N>`. If any test fails, stop — the
  toolchain/build is the problem, not your experiment.

Rebuild this C++ tree after any change to `CMakeLists.txt`, C++ headers,
C++ sources, CEC suite ports, `gsk_run`, `gsk_validate`, `gsk_list`, config
parsing, comparison logic, or C++ tests. A stale CLI executable can still launch
MATLAB with old seed, config, or verification behavior even when the source code
has already been edited.

If `cmake` / `g++` / `ctest` are **not** on PATH, use full paths and pass the
compiler explicitly (for example, with the MATLAB-bundled CMake and a WinLibs
g++):

```powershell
& "C:\path\to\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe" -S . -B build -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"
& "C:\path\to\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe" --build build -j
& "C:\path\to\mingw64\bin\ctest.exe" --test-dir build --output-on-failure
```

After the build, `build\` contains the four command-line tools plus the test
executables and the static library:

```text
build\gsk_list.exe        enumerate suites, optimizers, reference tables
build\gsk_validate.exe    validate ports / smoke-test suites / compare & verify results
build\gsk_run.exe         run an experiment (drives MATLAB) and auto-verify it
build\gsk_bench.exe       micro-benchmark the C++ port evaluate() throughput (no MATLAB)
build\libgskcec.a         the C++ support library
build\gskcec_*_tests.exe  the C++ unit tests (run via ctest)
```

This reference uses `gsk_list`, `gsk_validate`, and `gsk_run`; `gsk_bench` is the
timing tool documented in [performance.md](../research/performance.md).

Sanity-check the build (no MATLAB needed):

```powershell
build\gsk_list.exe --benchmarks
build\gsk_list.exe --optimizers
build\gsk_list.exe --references benchmarks\cec_reference_results
```

`--benchmarks` lists the five suites with their functions/dimensions;
`--optimizers` prints `gsk agsk apgsk atmals-gsk egsk fdb-agsk dt-gsk`;
`--references` prints one line per imported reference file plus `files=` /
`rows=` totals (currently `files=165`, `rows=1411`).

You can also smoke-test that each benchmark suite constructs and evaluates to
finite numbers (still no MATLAB, no optimizer):

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
build\gsk_validate.exe --suite cec2020 --smoke
build\gsk_validate.exe --suite cec2013 --smoke
build\gsk_validate.exe --suite cec2013lsgo --smoke
build\gsk_validate.exe --suite cec2011 --smoke
build\gsk_validate.exe --suite cec2013 --against saved_vectors
```

CEC2020 prints explicit `SKIP ...` lines for the few (function, dimension)
cells without reference data; that is expected, not a failure.

### 2.5 Build the MEX bridge

The MATLAB optimizers evaluate the C++ benchmarks through the `gskcec_eval`
**MEX** bridge. Build it once (needs MATLAB + the MinGW toolchain). The script
does **not** need the MATLAB `mex` command or a prior CMake build — it compiles
the benchmark sources directly:

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This produces `build\mex\gskcec_eval.mexw64`. The bridge is linked fully static
(`-static`, with the MATLAB import libraries `libmx.lib` / `libmex.lib` /
`libmat.lib` passed by full path), so it needs no MinGW runtime DLL
(`libwinpthread-1.dll`, `libstdc++`, `libgcc`) on PATH at load time. If the
script reports that it built the file but could not replace the existing one,
the bridge is still loaded in a MATLAB session (live problem handles keep it
locked): run `gskcec_eval('clear'); clear mex` in that session, or close MATLAB,
then rerun the script. If MATLAB or g++ are not auto-detected, pass them
explicitly:

```powershell
powershell -File scripts\build_mex_bridge.ps1 `
    -MatlabRoot "C:\path\to\MATLAB\R2025b" `
    -Gxx "C:\path\to\mingw64\bin\g++.exe"
```

(`-MatlabRoot` defaults to `matlab` on PATH or the `GSKCEC_MATLAB` env var;
`-Gxx` defaults to `g++` on PATH, then a search under the winget packages
folder.) The runner adds `build\mex` to the MATLAB path automatically; the
pure-MATLAB `sphere` suite needs no bridge.

Rebuild this MEX bridge after changes to CEC suite source files or
`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/`. It is a separate binary from
the C++ CLIs, so `cmake --build build -j` does not refresh
`build\mex\gskcec_eval.<mexext>`.

### 2.6 Putting MATLAB on PATH / passing --matlab

`gsk_run` locates MATLAB in this order: `--matlab <exe>`, then the
`GSKCEC_MATLAB` environment variable, then `matlab` on PATH. Pick one:

```powershell
# (a) add MATLAB to PATH for this shell
$env:Path = "C:\path\to\MATLAB\R2025b\bin;$env:Path"

# (b) set the env var the tooling and the MEX builder both read
$env:GSKCEC_MATLAB = "C:\path\to\MATLAB\R2025b\bin\matlab.exe"

# (c) or pass it per-invocation
build\gsk_run.exe --config configs\smoke.yml --root . `
    --matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"
```

For the **MATLAB IDE** path (A) you simply launch MATLAB and run the commands in
its Command Window — no PATH setup needed there.

### 2.7 Setting functions, dimensions, population, budget, runs, seed

This is the master mapping of "what knob sets what". The same five quantities
appear under three different names depending on whether you use a config, the
CLI flags, or the MATLAB runner.

| Quantity | Config key (`configs/*.yml`) | `gsk_run` flag | `run_experiment(...)` arg | Notes |
|---|---|---|---|---|
| Optimizer(s) | `optimizers: [gsk, ...]` | `--optimizer <name>` (one) | `'optimizer','gsk'` (one) | names: `gsk agsk apgsk atmals-gsk egsk fdb-agsk dt-gsk` |
| Suite | `suite: cec2017` | `--suite cec2017` | `'suite','cec2017'` | see [2.8](#28-suites-dimensions--default-budgets-reference) |
| Functions | `functions: [1, 3, ...]` or `all` | `--function N` (repeat) | `'functions',[1 3 ...]` | |
| Dimensions | `dimensions: [10, 30]` or `all` | `--dimension D` (repeat) | `'dimensions',[10 30]` | native-dim suites: use `0` |
| **Iterations (budget)** | `max_evaluations: M` (`0`=default) | `--max-evaluations M` | `'max_nfes',M` (`0`=default) | this is `max_nfes`, the evaluation budget; `M >= 0` |
| Runs | `runs: 51` | `--runs R` | `'runs',R` | whole integer `>= 1` |
| Base seed | `seed: 20240620` | `--seed S` | `'base_seed',S` | integer in `[0, 2^53]` (negative or non-integer values are rejected); per-run seeds also depend on seed policy |
| Seed policy | `seed_policy: reference` | `--seed-policy reference` | `'seed_policy','reference'` | `gsk_run` default is `reference`; direct `run_experiment` default is `unified`; DT-GSK always gets the unified schedule ([3.7](#37-dt-gsk)) |
| RNG family | `rand_generator: threefry` | `--rand-generator threefry` | `'rand_generator','threefry'` | overridden under `reference`: AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK use legacy `seed`; GSK uses `twister`. Under `unified`, MATLAB uses `threefry` when supported and falls back to `twister`. DT-GSK always uses `threefry` |
| Initial population | `np_init: N` (`0`=default) | `--np-init N` | `'np_init',N` (`[]`=default) | also `np_init` in `run_all_cec*.m` CONFIG and `run_all.ps1 -NpInit N`; integer `>= 12`, same NP for every optimizer ([population size](#population-size)) |
| Final population | `min_pop_size: M` (`0`=default) | `--min-pop-size M` | `'min_pop_size',M` (`[]`=default) | also `min_pop_size` in `run_all_cec*.m` CONFIG and `run_all.ps1 -MinPopSize M`; integer `>= 11`; AGSK/APGSK/FDB-AGSK/DT-GSK (GSK/eGSK/ATMALS-GSK ignore it) ([population size](#population-size)) |
| Dense best-so-far log | not supported | not supported | `'trace_points',n` (`0`=off) | also `trace_points = n` added to a `run_all_cec*.m` CONFIG (a commented line is there); writes `gen_logs/BestTrace_*.csv` at `n` log-spaced budgets for ERT/ECDF (`scripts/plot_performance.m`); the runs are unchanged |
| Dynamics trace | not supported | not supported | `'log_trace',true` (`'trace_rows',n`, default 200) | also `log_trace = true` added to a `run_all_cec*.m` CONFIG (a commented line is there); writes `trace/Dynamics_*.csv` (diversity, population size, adaptive parameters per generation) for `scripts/plot_dynamics.m`; the runs are unchanged |
| Algorithm settings (aliases) | not supported | not supported | `'optimizer','<alias>'` (`'aliases_file',path` for another file) | an `[alias]` in the root `algorithms.ini`: a base optimizer plus its own settings; use the alias in `run_all_cec*.m` `optimizers` ([aliases](#algorithm-aliases-algorithmsini)) |

`gsk_run` and shipped `configs/*.yml` use `seed_policy='reference'` for
published-table reproduction. The root `run_all_cec*.m` launchers use
`seed_policy='unified'` for new fair cross-family experiments. The reference
policy uses GSK/ATMALS-GSK/eGSK `base_seed + 9973*func + run-1` and
AGSK/APGSK/FDB-AGSK `D*func*run`; it also forces the effective generator to
legacy `seed` for AGSK/APGSK/FDB-AGSK/eGSK/ATMALS-GSK and `twister` for GSK.
Unified mode gives all optimizers the same seed, runner-generated initial
population, and post-initialization RNG state for the same `(D,function,run)`
cell, uses `threefry` when supported and otherwise `twister`, and verifies completed optimizer schedules with
`verify_unified_seed_schedule(...)`. Direct `run_experiment(...)` calls default
to `seed_policy='unified'` unless you pass a policy explicitly. Root
`run_all_cec*.m` launchers do not expose `base_seed`; they use
`run_experiment.m`'s centralized default `20240620`.
DT-GSK is the one exception to both policies: it is *unified-only*, so it gets
the unified seed and `threefry` under every `seed_policy`, and it draws its own
initial population instead of the runner's `X0` (see [3.7](#37-dt-gsk)).
Deterministic seeds are written to `summary/seed_schedule.csv`; the full policy
is in [seed_policy.md](../reference/seed_policy.md).

Unified-mode seed formula:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

Only `base_seed`, `dim`, `func`, and `run` enter that formula. Optimizer name,
optimizer index, population size, suite name, budget, and local-search settings
are deliberately excluded. The formula is evaluated with `uint64` arithmetic in
MATLAB (`get_cec_seed.m`) before conversion back to a MATLAB `double` seed.
For example, with the default base seed, `(D=30, F=7, run=12)` gives
`69241386` for every optimizer. The runner then draws the initial population
outside the optimizer, passes it as `X0`, and restores the random stream state
captured immediately after that draw. That is why unified mode is fair for new
cross-family experiments but should not be used for published-reference
reproduction.
Pass `'use_parallel',false|true` as needed; `gsk_run` and `scripts/run_all.ps1`
use serial execution by default.

<a id="population-size"></a>
**Population size.** By default each optimizer uses its **interface-default**
population (table below). `run_experiment(..., 'np_init', N)`, and the
`np_init` entry in the CONFIG block of each `run_all_cec*.m` launcher, set the
initial population of **every** optimizer to `N` (an integer `>= 12`, the
population floor of AGSK/APGSK/FDB-AGSK): the runner passes it as `options.np`
(`gsk`, `egsk`, `atmals-gsk`) or `options.np_init` (the others), and under
`unified` seeding the shared `X0` then has `N` rows. DT-GSK draws its own
population, and with the same `N` that draw equals the shared `X0`. So
`np_init = 100` runs all seven optimizers from the same start; for the six
optimizers whose default is 100 it changes nothing (results are identical).
A value other than an optimizer's default is a variant: the runner skips the
reference comparison table for it, records `np_init` in `run_config.json` and
`initial_population_policy`, and refuses to resume an output tree written with
another NP (use a new `output_dir` or `'overwrite',true`).
`run_experiment(..., 'min_pop_size', M)`, and the `min_pop_size` CONFIG entry,
set the **final** population size of the four optimizers that shrink their
population during the run: AGSK, APGSK and FDB-AGSK (default 12; `M` must not
exceed their initial NP) and DT-GSK (its `n_min`: 12, or 25 for `D >= 50`; its
`D >= 100` SP-NLPSR floor still applies). GSK, eGSK and ATMALS-GSK keep a fixed
population and ignore it, so one launcher value serves the whole family. `M`
is an integer `>= 11` (the AGSK/APGSK/FDB-AGSK senior partition needs it), and a
value other than an optimizer's default is a variant, handled like `np_init`.
Every CEC runner takes both: the config keys `np_init` / `min_pop_size`
(`0` = default), the `gsk_run` flags `--np-init` / `--min-pop-size`, and
`scripts/run_all.ps1 -NpInit` / `-MinPopSize` (override every config). A
nonzero value makes `gsk_run`'s automatic verification, and
`gsk_validate --verify` (which reads `np_init`/`min_pop_size` from
`environment.json`), a reduced protocol: the comparison with the published
tables is informational. To change any other variant parameter —
`kf`, `kr`, `k`, `p`, `fdb_case`, `protocol`, `use_fmincon`,
pools, ... — **or to set a custom single seed**, use the **lower-level MATLAB
path** shown in each algorithm's "(A) … lower-level snippet".
Interface-default populations:

| Optimizer | Default population | Set a custom one via |
|---|---|---|
| `gsk` | `np = 100` | `options.np` |
| `agsk` | `np_init = 100` (reference CEC2020 driver uses `40*D` for `D>5`) | `options.np_init` |
| `apgsk` | `np_init = 100` (`200*D`/`250` reference policy opt-in) | `options.np_init` |
| `atmals-gsk` | `np = 100` | `options.np` |
| `egsk` | `np = 100` | `options.np` |
| `fdb-agsk` | `np_init = 100` (`40*D` reference sphere harness opt-in) | `options.np_init` |
| `dt-gsk` | `NP = 5*D` initial, reduced nonlinearly to 12 (25 for `D >= 50`) | `options.np_init` (a variant, not the `pub` profile) |

All seven: `run_experiment(..., 'np_init', N)` or `np_init = N` in a launcher's CONFIG.
Final size (AGSK, APGSK, FDB-AGSK, DT-GSK): `'min_pop_size', M` or `min_pop_size = M`.

#### Algorithm aliases (`algorithms.ini`)

The launcher-wide `np_init` and `min_pop_size` change every listed optimizer.
To change one optimizer only, and keep its original results next to it,
define an alias in `algorithms.ini` in the repository root:

```ini
[gsk-np50]
base    = gsk
np_init = 50
```

and list it like an optimizer: `optimizers = {'gsk', 'gsk-np50'}` in a
`run_all_cec*.m` launcher, or `run_experiment('optimizer','gsk-np50', ...)`.
The alias runs the base's code with its settings, writes to its own results
folder (`results/_run_all/gsk-np50/<suite>/` from the launchers), uses the
base's seeds, and records `base_optimizer` and `alias_settings` in
`environment.json` and `run_config.json`. Its `np_init`/`min_pop_size` replace
the launcher's. The settings each base accepts (originals in brackets):

| Base | Settings |
|---|---|
| `gsk` | `np_init` (100), `kf` (0.5), `kr` (0.9), `k` (10), `p` (0.1) |
| `agsk`, `apgsk` | `np_init` (100), `min_pop_size` (12) |
| `fdb-agsk` | `np_init` (100), `min_pop_size` (12), `fdb_case` (1; 1 to 5) |
| `atmals-gsk` | `np_init` (100), `kf_pool` (0.2:0.1:0.8), `kr_pool` (0.85:0.01:1), `k_pool` (8:30), `p_pool` (0.05:0.01:0.15), `pls_pool` (1:0.1:2); each pool must contain 0.5, 0.9, 10, 0.1 and 1 |
| `egsk` | `np_init` (100), `kf1` (0.5), `kf2` (0.5), `kr` (1), `k` (10), `use_fmincon` (true) |
| `dt-gsk` | `np_init` (5*D), `min_pop_size` (12; 25 for D >= 50) |
| your own (e.g. `my-gsk`) | `np_init`, `min_pop_size`, and every option its main file reads (`options.<name>`, `isfield(options,'<name>')`, `local_option(options,'<name>',...)`) |

Values are numbers, lists `[0.3 0.5]`, ranges `0.2:0.1:0.8`, or
`true`/`false`; nothing is evaluated as code. Refused with
`run_experiment:args`: an unknown setting (the message lists the accepted
ones), `seed`, `rand_generator`, `initial_population`,
`rng_state_after_initialization`, `protocol`, `min_pop_size` for GSK/eGSK/
ATMALS-GSK, an alias named like an optimizer, and resuming a results folder
written with other alias settings. A file error names its line
(`read_algorithm_aliases:file`). Changed settings make the run a variant: the
in-run reference comparison is skipped. `gsk_run` and the YAML configs do not
read `algorithms.ini`.

**"Iterations".** GSK-family optimizers are population algorithms; the run
length is an **evaluation budget** `max_nfes`, not an iteration count. The
number of generations is `≈ max_nfes / population`. Leave the budget at `0`
(config/flag/arg) to use the suite default ([2.8](#28-suites-dimensions--default-budgets-reference)),
or set it explicitly to shorten/override a run.

### 2.8 Suites, dimensions & default budgets (reference)

| Suite | Functions | Dimensions | Default budget (`max_nfes`) | Optimum / error basis |
|---|---|---|---|---|
| `cec2017` | 1..30 (F2 excluded from default comparisons) | 10, 30, 50, 100 | `10000 * D` | known (`100*func`); stats over error, target 1e-8 |
| `cec2020` | 1..10 | 5, 10, 15, 20 | D5 50 000, D10 1 000 000, D15 3 000 000, D20 10 000 000 | known; stats over error, target 1e-8 |
| `cec2013` | 1..28 | 2,5,10,20,30,40,50,60,70,80,90,100 | `10000 * D` | known; stats over error, target 1e-8 |
| `cec2011` | 1..22 | **native per problem → use dimension `0`** | 150 000 | **no published optima**; stats over raw objective, `error`=NaN |
| `cec2013lsgo` | 1..15 | **native (1000 / 905) → use dimension `0`** | 3 000 000 | optima 0 by construction but tables are raw objectives; `error` = `best_fitness - 0` (the raw objective, no zero cutoff) |

Notes that bite in practice:

- **Native-dimension suites** (`cec2011`, `cec2013lsgo`): pass dimension `0`
  (CLI `--dimension 0`, config omit `dimensions:` or set `[0]`, runner
  `'dimensions',[0]`). Any nonzero dimension is rejected by `gsk_run`. They also
  emit a dimensionless rollup summary `<opt>_<suite>.csv`.
- **CEC2020 data gaps**: public functions 1 and 8 lack shuffle data at D=5 and
  D=15; those cells are reported as explicit `SKIP` lines (in `gsk_run`/MATLAB
  output and recorded in `environment.json` → `skipped_cells`), never silently
  dropped.
- **Default experiment matrix**: all seven optimizers on `cec2017` and
  `cec2011`; `agsk` additionally on `cec2020` (the shipped
  `configs\all_cec2017.yml` / `all_cec2011.yml` / `agsk_cec2020.yml`).
  `dt-gsk` on `cec2013`, `cec2013lsgo` and `cec2020` runs on request, against
  its imported tables ([3.7](#37-dt-gsk)). `cec2013` and `cec2013lsgo` are
  validation/extension suites, runnable on request. Optimizer/suite pairings the
  original reference sources never ran (e.g. `fdb-agsk`, whose reference ran a
  sphere harness, on the CEC suites) are framework-level extensions, not
  reproductions, even where an imported table exists to compare against.
- **Reference tables shipped** under `benchmarks\cec_reference_results`:
  `cec2017` has all seven optimizers at D10/30/50/100; `cec2011` has all seven
  (the native-dimension rollup `<opt>_cec2011.csv` plus per-dimension tables);
  `cec2013` has `gsk` and `dt-gsk` at D10/30/50; `cec2020` has `agsk` and
  `dt-gsk` at D5/10/15/20; `cec2013lsgo` has `dt-gsk` (D1000 and D905) besides
  the DECC-G and MOS baselines. `dt-gsk` is therefore the only optimizer with a
  table on every suite. When no reference table exists for an (optimizer,
  suite[, dim]) (any optimizer except `dt-gsk` on `cec2013lsgo`, optimizers
  other than `gsk`/`dt-gsk` on `cec2013` or at dimensions other than 10/30/50
  there, every optimizer except `agsk` and `dt-gsk` on `cec2020`), win/tie/loss
  are 0, `missing_reference` counts the unmatched functions, and the
  gross-deviation check cannot fire; the finiteness and (on known-optimum
  suites) sign checks still apply. See [2.9](#29-where-results-land) and each
  algorithm's "compare" subsection.

### 2.9 Where results land

`gsk_run` and `run_experiment` write the CEC-competition layout under the output
root, **one tree per `(optimizer, suite)`** (source: `gsk_run.cpp` builds
`out_root / optimizer / suite`; `run_experiment.m` writes the subfolders):

```text
results\<optimizer>\<suite>\
  summary\
    <optimizer>_<suite>_D<dim>.csv   per-dimension table: Function,Best,Median,Mean,Worst,SD
    <optimizer>_<suite>.csv          all functions in one table (native-dim suites only: cec2011, cec2013lsgo)
    per_run.csv                      full per-run record incl. seeds
    environment.json                 run environment + provenance (MATLAB command)
    verification.json                automatic CONSISTENT/DEVIATES verdict
  curves\
    Figure_F<func>_D<dim>_Run#<run>.csv   median run's convergence trace (Eval,BestError,Log10Error)
  gen_logs\
    CheckpointErrors_<optimizer>_F<func>_D<dim>.csv   per-run error at the CEC checkpoints (Run,Seed,E<nfes>...)
```

Column meanings (full schema: [result_schema.md](../reference/result_schema.md)):

- `summary/<opt>_<suite>_D<dim>.csv` — one row per function; `Best..SD`
  summarize **errors** when the suite has known optima, raw **objectives**
  otherwise (`statistics_basis` in `environment.json` records which). `SD` is
  the sample standard deviation. Numbers use `%.10E`.
- `summary/per_run.csv` —
  `optimizer,suite,function,dimension,run,seed,best_fitness,error,nfes,termination,runtime_seconds,max_nfes,rand_generator`.
  `error = best_fitness - optimum` with target-error zeroing; `NaN` on
  `cec2011` (no optima) and the raw objective on `cec2013lsgo` (optimum `0`).
  ATMALS-GSK on CEC2017 reports `abs(best_fitness - optimum)` error with the
  standard `1e-8` zero cutoff. `max_nfes` is the cell's effective budget and
  `rand_generator` the effective generator; `best_fitness`/`error` use `%.17g`.
- `curves/Figure_F*_D*_Run#*.csv` — `Eval,BestError,Log10Error` for the run
  nearest the median final value (`Log10Error` blank when `BestError <= 0`).
- `gen_logs/CheckpointErrors_*.csv` — `Run,Seed,E<c1>,E<c2>,...` at the standard
  CEC fractional checkpoints `[0.01 0.02 0.03 0.05 0.1 0.2 .. 1.0] * max_nfes`.
- `verification.json` — the verdict; see each algorithm's compare subsection and
  [5](#5-troubleshooting-appendix).

**Reruns, resume/add, and overwrite behavior.** Re-running an `(optimizer, suite)`
with overwrite disabled preserves the existing result tree. `run_experiment`
resumes from `summary/per_run.csv`, skips completed run ids whose stored seed,
budget and generator match the active run, appends missing runs, and archives
fixed-name refreshed artifacts under `_archive/<timestamp>/`.
Use `--overwrite`, `overwrite: true`, or `'overwrite',true` when you want a clean
replacement run: the previous active result tree is moved to
`_overwrite_archive/<suite>_<timestamp>/` under the same parent before the new
`summary/`, `curves/`, and `gen_logs/` folders are created.
Resume is seed-, budget- and generator-aware: a previous `per_run.csv` row is
reused only when its stored seed, `max_nfes` and `rand_generator` all match the
active run for that `(dimension,function,run)`. Changing the seed policy,
`--max-evaluations`, or the generator therefore re-runs those run ids and
appends fresh rows; the old rows remain in the file as audit history, and the
summary uses only the active rows. An `output_dir` inside
`benchmarks\cec_reference_results` is refused on every run
(`run_experiment:outputUnsafe`).

**Output root override.** Default is `<root>\results`. Change it with
`--output <dir>` (CLI; relative to the working directory) or `output_root:`
(config; a relative value resolves under `--root`) or `'output_dir',<dir>`
(runner; this is the full per-(opt,suite) directory in the runner's case, and a
relative value resolves against the current MATLAB folder).

---

## 3. Per-algorithm run guides

Each section gives **two independent run paths** — (A) MATLAB IDE and (B)
Windows terminal — plus the algorithm's options, prerequisites, expected
outputs, suites, common errors, and how to compare against the references.
Shared steps (build, MEX bridge, MATLAB location, output layout) are in
[section 2](#2-common-setup).

All seven share these run-path templates; only the optimizer name, options,
suites and quirks differ.

- **(A) MATLAB IDE — high level.** `cd` into `src/runners`, call
  `run_experiment(...)`. Uses interface-default population and the documented
  per-run seed policy. Set functions/dimensions/budget/runs/seed via its
  arguments (see [2.7](#27-setting-functions-dimensions-population-budget-runs-seed)).
- **(A) MATLAB IDE — lower level.** Build a `problem` with
  `gskcec_make_problem(suite, func, dim, project_root, max_nfes)` and call
  `<name>_optimize(problem, options)` directly. This is the **only** way to set
  population and other variant options, or a custom single seed.
- **(B) Terminal.** `build\gsk_run.exe` with a `--config` file **or** explicit
  flags; it validates, runs MATLAB, then auto-verifies.

What appears in the MATLAB Command Window during a run (all optimizers): one
progress line per run, e.g.
`gsk cec2017 f1 D10 run 1/3: best=... error=... nfes=... (0.4s)`, then
`run_experiment: wrote <output_dir>`. `SKIP <suite> fN Dd: <reason>` lines
appear for unavailable cells.

### 3.1 gsk

Baseline Gaining-Sharing Knowledge. Entry point
`src/optimizers/gsk/gsk_optimize.m`. Options (all optional; reference defaults):
`np` (100), `kf` (0.5), `kr` (0.9), `k` (10), `p` (0.1). `options.seed` is
**required**. `termination` is always `'max_evaluations'` (GSK never stops
early; the final error is zeroed below the target).

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. No toolbox.

#### (A) MATLAB IDE

High-level (reference-default `np=100`, derived per-run seeds), CEC2017 F1 & F3
at D=10, 3 runs:

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',3, 'base_seed',20240620, ...
    'max_nfes',0, ...   % 0 = suite default = 10000*D
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/gsk/cec2017', ...
    'overwrite',true)
```

Lower-level (full control: custom population, custom budget, custom single
seed). This is how you set `np`, `kf`, `kr`, `k`, `p`:

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src')));          % optimizers + helpers
addpath(fullfile(root,'build','mex'));           % the gskcec_eval bridge

% problem(suite, func_id, dim, project_root, max_nfes_override)
problem = gskcec_make_problem('cec2017', 1, 10, root, 50000);  % budget override = 50000

options = struct('seed', 777, 'np', 100, 'kf', 0.5, 'kr', 0.9, 'k', 10, 'p', 0.1);
result  = gsk_optimize(problem, options);

fprintf('best=%.6e error=%.6e nfes=%d term=%s\n', ...
    result.best_fitness, result.error, result.nfes, result.termination);
gskcec_eval('free', problem.mex_handle);          % release the C++ benchmark handle
```

`result` fields: `optimizer, suite, func_id, dim, seed, best_x, best_fitness,
error, nfes, termination, convergence(.nfes,.best_fitness), runtime_seconds,
params, notes` (contract: [matlab_interface.md](../reference/matlab_interface.md)).

#### (B) Terminal

Config form (smoke = 1 function, tiny budget):

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

Explicit-flags form (CEC2017 F1, D=10, 3 runs, default budget):

```powershell
build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 `
    --function 1 --runs 3 --seed 20240620 --overwrite
```

Point at MATLAB if not on PATH: add `--matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"`.
Preview without running: add `--dry-run` (prints the exact MATLAB `-batch`
command; needs neither MATLAB nor the bridge).

**Auto-verification output.** After the run, `gsk_run` prints, e.g.:

```text
gsk_run: verify gsk on cec2017 -> CONSISTENT (reduced budget); win/tie/loss=0/0/1, hard_failures=0
```

and writes `results\gsk\cec2017\summary\verification.json` or the next available
`verification_<n>.json` if a prior verdict already exists. A tiny smoke run is a
*reduced-budget* run (override budget or `< 25` runs), so the win/tie/loss tally
and the gross-deviation check are informational — a short run is legitimately
worse than the full published table. `gsk_run` exits nonzero only on `DEVIATES`.

#### Outputs, suites, errors, comparison

- **Outputs.** `results\gsk\cec2017\summary\gsk_cec2017_D10.csv` (+ other dims if
  requested), `per_run.csv`, `environment.json`, `verification.json`;
  `curves\Figure_F1_D10_Run#<med>.csv`; `gen_logs\CheckpointErrors_gsk_F1_D10.csv`.
- **Suites.** Reproduce on **CEC2017** (`--dimension 10|30|50|100`), **CEC2011**
  (`--dimension 0`), and optionally **CEC2013** (`--dimension 2|...|100`),
  **CEC2013LSGO** (`--dimension 0`), **CEC2020** (`--dimension 5|10|15|20`).
  Reference tables for verification exist for `gsk` on `cec2017`
  (D10/30/50/100), `cec2011` (native), and `cec2013` at D10/30/50 only. Other
  `gsk` selections (CEC2013 at D2/5/20/40/60-100, CEC2013LSGO, CEC2020) match no
  table: they count as `missing_reference`, and the gross-deviation check cannot
  fire for them (the finiteness and sign checks still apply).
- **Common errors.** See [5](#5-troubleshooting-appendix): MEX bridge missing,
  MATLAB not found, or unsupported benchmark/function/dimension selections.
- **Compare to references.** Side-by-side numbers vs the published `gsk` tables:

  ```powershell
  build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
  ```

  The `--compare` walk skips `_overwrite_archive\` and `_archive\` folders below
  the results root, so archived copies are not counted as live rows.

  Re-check a single run directory's verdict without re-running the optimizer:

  ```powershell
  build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results
  ```

  Read it: lower mean is better; a `tie` is within relative `1e-8`; `win`/`loss`
  are vs the published mean. Without a flag, `--verify` reads the protocol
  (`runs`, `max_nfes_override`) from the run's `summary\environment.json`, using
  the same rule as `gsk_run`, and falls back to the full protocol when that file
  is absent; it prints `protocol from: <source>`. `--reduced` / `--full` only
  override it (`--full` makes the gross-deviation check a hard failure).
  (`--verify` writes the next available `verification*.json` file and exits
  nonzero on `DEVIATES`.)

### 3.2 agsk

Adaptive GSK (parameter-pool adaptation + nonlinear population reduction). Entry
point `src/optimizers/agsk/agsk_optimize.m`. Options: `np_init` (100),
`min_pop_size` (12); the KF/KR pools and the 0.05 senior partition are fixed
reference values. `options.seed` required. AGSK **can** stop early
(`'target_error_reached'`) when it reaches the target.

> **CEC2020 reproduction quirk.** The reference CEC2020 driver sets
> `pop_size = 40*D` for `D>5` (else 100). `run_experiment` / `gsk_run` use the
> interface default `np_init=100`. To reproduce the *published* CEC2020 numbers
> you must pass `options.np_init = 40*D` via the lower-level MATLAB path.

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. No toolbox.

#### (A) MATLAB IDE

High-level (CEC2017, all default dims, 51 runs is the full study — shown small
here):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','agsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',5, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/agsk/cec2017', 'overwrite',true)
```

CEC2020 high-level (its native suite; default `np_init=100`, **not** the `40*D`
reference rule — see quirk above):

```matlab
run_experiment('optimizer','agsk', 'suite','cec2020', ...
    'functions',[1 2 3], 'dimensions',[10], 'runs',5, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/agsk/cec2020', 'overwrite',true)
```

Lower-level (reproduce the CEC2020 `40*D` population, custom seed):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
D = 10;
problem = gskcec_make_problem('cec2020', 2, D, root, 0);     % 0 = suite default budget (D10 = 1e6)
options = struct('seed', 42, 'np_init', 40*D, 'min_pop_size', 12);   % reference CEC2020 population rule
result  = agsk_optimize(problem, options);
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
# AGSK on its native CEC2020 (the ready-made full config: D 5/10/15/20, 30 runs)
build\gsk_run.exe --config configs\agsk_cec2020.yml --root .

# Explicit flags, CEC2017 F1 D30, 5 runs
build\gsk_run.exe --optimizer agsk --suite cec2017 --dimension 30 --function 1 --runs 5 --seed 20240620 --overwrite
```

Auto-verification: `agsk on cec2020` is verified against the published `agsk`
table (the only other CEC2020 reference is `dt-gsk`'s). On CEC2017, `agsk` has
a reference table too.

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\agsk\<suite>\`. CEC2020 runs may include
  `SKIP` lines (F1/F8 at D5/D15) recorded in `environment.json`.
- **Suites.** **CEC2017**, **CEC2011** (`--dimension 0`), **CEC2020**
  (`--dimension 5|10|15|20`), optionally CEC2013 / CEC2013LSGO. Verification
  references exist for `agsk` on `cec2017`, `cec2011`, and `cec2020`.
- **Compare.** Same `--compare` / `--verify` commands as 3.1, pointed at
  `results\agsk\...`. Because AGSK's reduced runs can reach the target early,
  expect `termination=target_error_reached` rows in `per_run.csv` on easy
  functions.

### 3.3 apgsk

GSK with Adaptive Parameters (separate implementation, not an AGSK flag):
negative secondary KF pool, stochastic scalar junior schedule, and an opt-in
large reference population policy. Entry point
`src/optimizers/apgsk/apgsk_optimize.m`. Options: `np_init` (default 100;
`200*D`/`250` reference policy opt-in), `min_pop_size` (12); pools fixed.
`options.seed` required. Can stop early (`'target_error_reached'`).

> **Big population warning.** The opt-in `200*D` policy is large (e.g. D=100
> gives NP=20000). Generations are roughly `max_nfes/NP`; at the full CEC2017
> budget `10000*D=1e6`, D=100 gives only ~50 generations.

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. No toolbox.

#### (A) MATLAB IDE

High-level (CEC2017 F1 D10, default `np_init=100`):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','apgsk', 'suite','cec2017', ...
    'functions',[1], 'dimensions',[10], 'runs',5, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/apgsk/cec2017', 'overwrite',true)
```

Lower-level (opt into the APGSK reference-release population policy):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
problem = gskcec_make_problem('cec2017', 1, 10, root, 0);
options = struct('seed', 99, 'np_init', 200*10, 'min_pop_size', 12);   % opt-in reference-release population
result  = apgsk_optimize(problem, options);
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
build\gsk_run.exe --optimizer apgsk --suite cec2017 --dimension 10 --function 1 --runs 5 --seed 20240620 --overwrite
# CEC2011 (native dims -> 0)
build\gsk_run.exe --optimizer apgsk --suite cec2011 --dimension 0 --runs 3 --seed 20240620 --max-evaluations 150000 --overwrite
```

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\apgsk\<suite>\`.
- **Suites.** **CEC2017**, **CEC2011** (`--dimension 0`), optionally CEC2013 /
  CEC2013LSGO / CEC2020. Verification references for `apgsk` exist for
  `cec2017` and `cec2011`; CEC2013, CEC2013LSGO, and CEC2020 runs get
  `missing_reference` (no gross-deviation check).
- **Compare.** Same `--compare` / `--verify` as 3.1, pointed at
  `results\apgsk\...`.

### 3.4 atmals-gsk

Adaptive GSK with memory-based parameter selection (probability tables +
roulette) and a best-solution local search. Entry point
`src/optimizers/atmals-gsk/atmals_gsk_optimize.m`. **Key option:**
`options.protocol` = `'cec2017'` (default) **or** `'cec2011'`, selecting which
reference driver behavior is reproduced (G_Max, the mean-fitness signal, the
senior partition, the local-search clip, and a D==1 branch differ). Other
overridable options: `np` (100), `kf_pool`, `kr_pool`, `k_pool`, `p_pool`,
`pls_pool`. `options.seed` required. `termination` always `'max_evaluations'`.

`run_experiment` and `gsk_run` auto-select the ATMALS protocol for the two
published suites: `protocol='cec2017'` on CEC2017 and `protocol='cec2011'` on
CEC2011. Lower-level MATLAB calls may still pass `options.protocol` explicitly
for controlled checks.

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. **No toolbox** (the
Fuzzy Logic `gaussmf` is replaced by `atmals_gaussmf.m`).

#### (A) MATLAB IDE

High-level (CEC2017, default `'cec2017'` protocol):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','atmals-gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',5, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/atmals-gsk/cec2017', 'overwrite',true)
```

Lower-level on **CEC2011 with the matching protocol** (the faithful CEC2011
reproduction):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
problem = gskcec_make_problem('cec2011', 1, 0, root, 150000);   % native dim (0), CEC2011 budget
options = struct('seed', 2025, 'protocol', 'cec2011', 'np', 100);
result  = atmals_gsk_optimize(problem, options);                % error = NaN (no published optimum)
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
# CEC2017 (uses the default 'cec2017' protocol)
build\gsk_run.exe --optimizer atmals-gsk --suite cec2017 --dimension 10 --function 1 --runs 5 --seed 20240620 --overwrite

# CEC2011 via the full config (runner auto-selects protocol='cec2011')
build\gsk_run.exe --config configs\all_cec2011.yml --root .
```

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\atmals-gsk\<suite>\`. On CEC2011 the
  `error` column is `NaN` and statistics are over raw objectives; a
  dimensionless rollup `atmals-gsk_cec2011.csv` is also written.
- **Suites.** **CEC2017** (protocol `cec2017`), **CEC2011**
  (protocol `cec2011`, `--dimension 0`), optionally CEC2013 / CEC2020 /
  CEC2013LSGO. Verification references for `atmals-gsk` exist for **both**
  `cec2017` and `cec2011` (the `atmals-gsk` reference folder).
- **Compare.** `--compare` / `--verify` as 3.1, pointed at
  `results\atmals-gsk\...`. The summary file names carry the hyphenated slug
  `atmals-gsk`, which is exactly the reference folder name, so no mapping is
  needed.

### 3.5 egsk

Enhanced GSK: separate junior/senior knowledge factors, late-stage
membership-based factor adaptation, a population-level selection twist, and an
**fmincon (SQP) IP local refinement**. Entry point
`src/optimizers/egsk/egsk_optimize.m`. Options: `use_fmincon` (`true` reference
default; `false` only for explicit non-reference diagnostics), `np` (100),
`kf1`/`kf2` (0.5), `kr` (1), `k` (10). `options.seed` required.
`termination` always `'max_evaluations'`.

> **Toolbox behavior.** Reference-mode eGSK requires
> `license('test','Optimization_Toolbox') && exist('fmincon','file')`. With the
> toolbox present, the IP stage runs and `result.notes` is empty; its evaluations
> are counted, so `result.nfes` can slightly exceed `max_nfes` (reference
> behavior). With the toolbox **absent**, the default call fails with
> `egsk:fminconUnavailable`. Passing `options.use_fmincon=false` skips IP only
> for explicit non-reference diagnostics and records
> `'IP refinement disabled via options.use_fmincon (non-reference diagnostic mode)'`.

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB + Optimization
Toolbox (`fmincon`) for reference-mode eGSK.

#### (A) MATLAB IDE

High-level (CEC2017; requires fmincon):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','egsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',5, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/egsk/cec2017', 'overwrite',true)
```

Lower-level (explicit non-reference no-IP diagnostic path):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
problem = gskcec_make_problem('cec2017', 1, 10, root, 0);
options = struct('seed', 7, 'np', 100, 'use_fmincon', false);   % non-reference diagnostic: skip IP
result  = egsk_optimize(problem, options);
fprintf('notes: %s\n', result.notes);     % -> non-reference diagnostic note
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
build\gsk_run.exe --optimizer egsk --suite cec2017 --dimension 10 --function 1 --runs 5 --seed 20240620 --overwrite
```

(`gsk_run` cannot set `use_fmincon`; it runs the reference-mode path and
therefore requires `fmincon`.)

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\egsk\<suite>\`. Watch
  `environment.json` → `optimizer_notes` for whether IP ran.
- **Suites.** **CEC2017**, **CEC2011** (`--dimension 0`), optionally CEC2013 /
  CEC2020 / CEC2013LSGO. Verification references for `egsk` exist for `cec2017`
  and `cec2011`.
- **Compare.** `--compare` / `--verify` as 3.1, pointed at `results\egsk\...`.

### 3.6 fdb-agsk

AGSK machinery with Fitness-Distance Balance guide selection injected into the
donor indices; all five reference cases. Entry point
`src/optimizers/fdb-agsk/fdb_agsk_optimize.m`. Options: `fdb_case` (1..5,
default 1), `np_init` (default 100; `40*D` reference sphere harness opt-in),
`min_pop_size` (12). `options.seed` required. `termination` always
`'max_evaluations'`.

> **Budget vs population constraint (read before tiny runs).** The original
> reference flow assumes `np_init < 0.1*max_nfes`. This holds for `40*D` vs
> `1000*D`; the port also has an `isempty(KW_ind)` phase guard so reduced-budget
> runs are robust. For reference-like checks, still keep `max_nfes` large enough
> that `np_init < 0.1*max_nfes`.
>
> **Framework extension.** The reference ran FDB-AGSK on a sphere harness only;
> running it on the CEC suites is a framework-level extension, **not** a
> reference-validated reproduction. Reference tables for FDB-AGSK do ship under
> `benchmarks\cec_reference_results\cec2017\fdb-agsk\` (D10/30/50/100) and
> `cec2011\fdb-agsk\`, so `--compare` / `--verify` produce real win/tie/loss
> verdicts against them (cite their provenance as described in
> `benchmarks/cec_reference_results/README.md`).

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. No toolbox.

#### (A) MATLAB IDE

High-level (CEC2017 F1 D10; default `fdb_case=1`, `np_init=100`):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','fdb-agsk', 'suite','cec2017', ...
    'functions',[1], 'dimensions',[10], 'runs',3, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/fdb-agsk/cec2017', 'overwrite',true)
```

Lower-level (choose a case, small population, safe budget):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
problem = gskcec_make_problem('cec2017', 1, 10, root, 20000);   % 20000 > 10*0.1*... ; safe for np_init=100
options = struct('seed', 5, 'fdb_case', 3, 'np_init', 100, 'min_pop_size', 12);  % case in 1..5
result  = fdb_agsk_optimize(problem, options);
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
build\gsk_run.exe --optimizer fdb-agsk --suite cec2017 --dimension 10 --function 1 --runs 3 --seed 20240620 --overwrite
```

(`gsk_run` cannot set `fdb_case`; the runner uses the default case 1. Use the
lower-level path to select cases 2..5.)

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\fdb-agsk\<suite>\`.
- **Suites.** **CEC2017**, **CEC2011** (`--dimension 0`), optionally CEC2013 /
  CEC2020 / CEC2013LSGO — all framework extensions.
- **Compare.** `--compare` / `--verify` as 3.1, pointed at
  `results\fdb-agsk\...`; CEC2017 and CEC2011 cells are compared against the
  shipped `fdb-agsk` tables (real win/tie/loss, and at full protocol the
  gross-deviation check can return `DEVIATES`); CEC2013, CEC2013LSGO, and
  CEC2020 cells count as `missing_reference`. The summary file names carry the
  hyphenated slug `fdb-agsk`, which is the reference folder name.

### 3.7 dt-gsk

Dimension-Tiered GSK: the GSK junior/senior operators plus adaptive
configuration selection, nonlinear population reduction, linkage-aware
crossover, budget-safe escapes and restarts, and deterministic local
refinement, each switched on by the dimension tier. Entry point
`src/optimizers/dt-gsk/dt_gsk_optimize.m`; the folder holds three code files
(`dt_gsk_optimize.m`, the `pub` profile `dt_gsk_config.m`, and the interaction
graph `dt_gsk_graph.m` used from `D = 50`). It is a port of the DT-GSK reference
implementation v2.46 (MIT license), not of a MATLAB release; its
[README](../../src/optimizers/dt-gsk/README.md) is the authoritative summary of
behavior and validation, and [dt-gsk.md](../algorithms/dt-gsk.md) is the
algorithm page.

Options: `seed` (required) and `rand_generator`, which must be `threefry`
(empty/`auto`/`default` are accepted; anything else raises
`dt_gsk_optimize:options`). Every other setting comes
from the `pub` profile for the problem's tier (`D < 20`, `20 <= D < 50`,
`D >= 50`, `D >= 100`; the tier table is in the README). The initial population
is `NP = 5*D`; the optional `options.np_init` (integer >= 5), or
`run_experiment(..., 'np_init', 100)`, replaces it. That is a variant, not the
published setting: the runner skips its reference comparison table and refuses
to resume an output tree written with another NP. `termination` is always `'max_evaluations'` and `nfes` ends
exactly at `max_nfes`; `error = best_fitness - optimum`, zeroed below the
target, `NaN` without a known optimum.

> **Unified-only seeding (fair-start exception).** `run_experiment` schedules
> DT-GSK with `get_cec_seed(base_seed, dim, func, run)` and `threefry` under
> **every** `seed_policy` (`reference`, `unified`, `native`, `derived`),
> mirroring the reference implementation's `UNIFIED_ONLY_OPTIMIZERS`: that is how its
> reference campaigns were produced. `gsk_run`'s default
> `--seed-policy reference` therefore reproduces the reference seeds, and
> `--rand-generator` has no effect on DT-GSK. DT-GSK derives named Threefry
> substreams from the run seed and samples its own initial population: the
> runner draws no `X0` for it, and a supplied `options.initial_population` is
> ignored. `environment.json`, `run_config.json` and `phase0_protocol.json`
> record `initial_population_policy` as `optimizer self-initializes NP = 5*D
> ...`, and `run_config.json` records `profile: "pub"`.

**Prerequisites.** Build (2.4) + MEX bridge (2.5) + MATLAB. No toolbox for the
optimizer; the per-run comparison below needs the Statistics and Machine
Learning Toolbox.

#### (A) MATLAB IDE

High-level (CEC2017 F1 & F3 at D10, 3 runs):

```matlab
cd('<repo>/gsk_family/src/runners')
run_experiment('optimizer','dt-gsk', 'suite','cec2017', ...
    'functions',[1 3], 'dimensions',[10], 'runs',3, 'base_seed',20240620, 'max_nfes',0, ...
    'project_root','<repo>/gsk_family', ...
    'output_dir','<repo>/gsk_family/results/dt-gsk/cec2017', 'overwrite',true)
```

Lower-level (one run with the runner's seed; only `seed` and `rand_generator`
are read from `options`):

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'build','mex'));
problem = gskcec_make_problem('cec2017', 1, 30, root, 0);      % D=30: tier 20 <= D < 50
options = struct('seed', get_cec_seed(20240620, 30, 1, 1), 'rand_generator', 'threefry');
result  = dt_gsk_optimize(problem, options);                   % result.params.profile = 'pub'
gskcec_eval('free', problem.mex_handle);
```

#### (B) Terminal

```powershell
# One small cell
build\gsk_run.exe --optimizer dt-gsk --suite cec2017 --dimension 10 --function 1 --runs 3 --seed 20240620 --overwrite

# The full CEC2017 protocol of the imported reference: D10/30/50/100, F2 excluded, 51 runs
build\gsk_run.exe --optimizer dt-gsk --suite cec2017 --runs 51 --seed 20240620
```

`dt-gsk` is also part of `configs\all_cec2017.yml` and `all_cec2011.yml`
(section 4); a config of your own with `optimizers: [dt-gsk]` works the same
way. The runner drops CEC2017 F2, so the full run covers the same 29 functions
x 4 dimensions x 51 runs as the reference evidence.

#### Outputs, suites, errors, comparison

- **Outputs.** As in 3.1 under `results\dt-gsk\<suite>\` (launchers:
  `results\_run_all\dt-gsk\<suite>\`). `per_run.csv` rows always show
  `termination=max_evaluations` and `rand_generator=threefry`;
  `environment.json` → `optimizer_notes` carries `self-init (fair-start
  exception)` for the runs executed in that session.
- **Suites.** All five. DT-GSK is the only optimizer with imported reference
  tables on every suite: `cec2017` (D10/30/50/100, 51 runs), `cec2013`
  (D10/30/50, 51 runs), `cec2020` (D5/10/15/20, 30 runs), `cec2011` (native
  dims plus rollup, 25 runs) and `cec2013lsgo` (D1000/D905, 25 runs), imported
  from the reference implementation (provenance:
  `benchmarks\cec_reference_results\cec2017\dt-gsk\PROVENANCE.md`). They are
  cross-implementation evidence, produced by the reference implementation, not
  by this toolkit.
- **Common errors.** `dt_gsk_optimize:options` for a non-Threefry
  `rand_generator` or a missing seed (lower-level path only; the runner always
  passes `threefry`). The ignored `X0` is expected, not an error. See
  [5](#5-troubleshooting-appendix).
- **Compare (aggregate).** `--compare` / `--verify` as 3.1, pointed at
  `results\dt-gsk\...`; every suite has `dt-gsk` tables, produced at the
  reference's full protocol.
- **Compare (per run).** For CEC2017 the reference evidence also holds
  `evidence\per_run.csv` (every run with its seed), so a full campaign can be
  compared run by run with `scripts/compare_reference_runs.m` (MATLAB, Statistics
  and Machine Learning Toolbox):

  ```matlab
  cd('<repo>/gsk_family'); addpath('scripts')
  report = compare_reference_runs('results/dt-gsk/cec2017', ...   % or results/_run_all/dt-gsk/cec2017
      'benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv', ...
      'out', 'results/dt-gsk/cec2017_vs_reference.csv');
  ```

  Each argument is a `per_run.csv` path or a folder holding `summary\per_run.csv`
  (or `per_run.csv`); for duplicate (dimension, function, run) rows from resumed
  runs the last row counts. For every (dimension, function) cell in both sets it
  prints Best/Median/Mean on each side (errors, or raw objectives where `error`
  is `NaN`), whether Best, Median and Mean each agree to within one order of
  magnitude (`'decades'`, default 1; values below `'zero_tol'` = `1e-8` count
  as 0; both sides are first rounded to `'sig_digits'` = 11 significant digits,
  the precision of the reference file, so last-digit noise is not a
  difference), and
  the two-sided Wilcoxon rank-sum p-value (`ranksum`) at `'alpha'` (default
  `0.05`); a cell is `MATCH` when both checks pass, else `DIFFERS`. When both
  sides used the same seed for each run (true here: both use the unified
  schedule), the paired signed-rank p-value is added for information. A final
  line counts the cells still significant after a Holm adjustment across all
  cells (about `alpha` x cells raw rejections are expected by chance). The
  returned `report.table` (and the `'out'` CSV) holds every column, including
  `p_holm`. Expect statistical, not bit-for-bit, agreement: MATLAB's Threefry
  generator produces the same 64-bit words as the reference implementation's
  generator but converts them to
  doubles differently (at most `2^-53` per uniform draw), so live trajectories
  separate once a last-bit difference flips a discrete decision. Results of the
  CEC2017 campaign are recorded in the DT-GSK README.

---

## 4. Reproduce the default matrix

The default experiment matrix is: all seven optimizers on **CEC2017** and
**CEC2011**, plus **AGSK on CEC2020**. The ready-made configs encode the full
run counts (CEC2017: 51 runs; CEC2011: 25 runs; CEC2020 AGSK: 30 runs). These
are long runs — start them when you can leave the machine. DT-GSK runs inside
these configs with its own unified-only seeding; its other suites and the
per-run comparison against its imported reference are in [3.7](#37-dt-gsk).

Prerequisites: complete [2.4](#24-build-the-c-clis-cmake--ctest) (build) and
[2.5](#25-build-the-mex-bridge) (MEX bridge), and make MATLAB locatable
([2.6](#26-putting-matlab-on-path--passing---matlab)).

```powershell
# 1. Full CEC2017 matrix: all seven optimizers x D{10,30,50,100}; F2 excluded
build\gsk_run.exe --config configs\all_cec2017.yml --root .

# 2. Full CEC2011 matrix: all seven optimizers x problems 1..22 (native dims) x 25 runs, budget 150000
build\gsk_run.exe --config configs\all_cec2011.yml --root .

# 3. AGSK on CEC2020 (its native suite): D{5,10,15,20} x F{1..10} x 30 runs
build\gsk_run.exe --config configs\agsk_cec2020.yml --root .
```

Each config drives one MATLAB invocation per optimizer and auto-verifies every
`(optimizer, suite)` against its reference table (where one exists). Every
optimizer in a config is run and verified even after an earlier one fails or
`DEVIATES`; `gsk_run` then prints a per-optimizer summary and exits with the
first nonzero code (1 MATLAB failure, 2 verification error, 3 `DEVIATES` or no
summary).

Then compare everything against the published references in one pass and write a
CSV:

```powershell
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

This walks every `results\<opt>\<suite>\summary\<opt>_<suite>_D<dim>.csv`
(skipping `_overwrite_archive\` and `_archive\` folders below the results root),
takes optimizer, suite and dimension from the file name, matches each to its
published table by (suite, algorithm, dimension), and prints one line per
comparable (function, dimension):

```text
gsk cec2017 f1 D10 mean=<your mean> ref_mean=<published mean> rel_diff=<...> -> <win|tie|loss>
...
compared=<N> win=<...> tie=<...> loss=<...> no_reference=<...>
```

`no_reference` counts functions with no published table for that optimizer/suite
(e.g. any optimizer except `dt-gsk` on CEC2013LSGO, optimizers other than
`gsk`/`dt-gsk` on CEC2013, any optimizer except `agsk` and `dt-gsk` on CEC2020;
see [2.8](#28-suites-dimensions--default-budgets-reference)).
Lower mean is better; `tie` is within relative `1e-8`. `--compare` works on
per-function means; for a run-by-run statistical comparison of a campaign with
an imported per-run record, use `scripts/compare_reference_runs.m`
([3.7](#37-dt-gsk)).

Optional: generate the comparison tables, Friedman/Wilcoxon stats, and box/
convergence figures (toolbox-free) with the MATLAB analysis script:

```matlab
cd('<repo>/gsk_family/scripts')
analyze_results('project_root','<repo>/gsk_family', ...
                'results_root','<repo>/gsk_family/results', ...
                'reference_root','<repo>/gsk_family/benchmarks/cec_reference_results', ...
                'output_dir','<repo>/gsk_family/results/analysis')
```

It writes `comparison_table.csv`, `friedman_ranks.csv`,
`wilcoxon_vs_reference.csv`, and `fig_<suite>_D<dim>_boxplot.pdf` /
`fig_<suite>_D<dim>_convergence.pdf` under the output dir. `_archive\` and
`_overwrite_archive\` trees are ignored, and each run is matched only to the
reference table of its exact dimension (no table: blank `reference_mean`,
`insufficient_reference`). With `results_root` at `<root>/results`, both
`results\<opt>\<suite>` (`gsk_run`) and `results\_run_all\<opt>\<suite>`
(launchers) are read; a duplicate (optimizer, suite, dimension) prints a
`WARNING` and is labeled by its path (`_run_all/gsk` vs `gsk`). Use
`results_root = <root>/results/_run_all` (or `<root>/results/<opt>`) to analyze
one layout only. Tie ranks come from a local helper, so no Statistics Toolbox is
needed.

---

## 5. Troubleshooting appendix

| Symptom | Cause | Fix |
|---|---|---|
| `gskcec:mexMissingPrerequisite` / `gskcec:mexMissing` | The MEX bridge was never built, or `build\mex\gskcec_eval.<mexext>` is missing. `run_all_cec*.m` and `run_experiment` stop at startup for this global prerequisite so they do not write partial all-skipped CEC results. | Build it: `powershell -File scripts\build_mex_bridge.ps1` (2.5), or follow the checklist in `build.txt`. `run_experiment` auto-adds `build\mex`; for the lower-level `gskcec_make_problem` path add it yourself: `addpath('<root>/build/mex')`. The pure-MATLAB `sphere` suite needs no bridge. |
| `gskcec:mexNotLoadable` | The bridge file exists but MATLAB cannot load it; the startup gate (`gskcec_require_mex`) forces a real load. A bridge built by the old script imports `libwinpthread-1.dll` and fails with `Invalid MEX-file ... The specified module could not be found.` when no MinGW `bin` folder is on PATH. | Rebuild with `powershell -File scripts\build_mex_bridge.ps1` (2.5), which links `-static` and needs no MinGW runtime DLL. If the script cannot replace the file, run `gskcec_eval('clear'); clear mex` in MATLAB (live handles keep the bridge locked) or close MATLAB, then retry. |
| `run_experiment:outputUnsafe` | `output_dir` is inside (or equal to) `benchmarks\cec_reference_results`; refused on every run, before anything is created. | Write results under `results\` (or any other folder outside the imported reference tree). |
| `gsk_run: MATLAB invocation failed` / MATLAB not found | MATLAB not on PATH and neither `--matlab` nor `GSKCEC_MATLAB` set. | Pass `--matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"`, or set `$env:GSKCEC_MATLAB`, or add `...\bin` to PATH (2.6). |
| Existing result tree is reused | This is intentional. The runner resumes from `summary/per_run.csv`, skips completed run ids whose stored seed, budget (`max_nfes`) and generator match the active run (other rows are re-run and appended), appends missing runs, and archives refreshed fixed-name artifacts under `_archive/<timestamp>/`. | Choose a new `--output` / `output_dir` only when you want a separate experiment tree. |
| `SKIP <suite> fN Dd: ...` lines during a run | That (function, dimension) cell has no reference/benchmark data (e.g. CEC2020 F1/F8 at D5/D15). | Expected and explicit; the cell is recorded in `environment.json` → `skipped_cells` and excluded from summaries. Not an error. |
| Verdict `DEVIATES`, `gsk_run` exits nonzero | A **hard-failure** check fired: non-finite statistic; (known-optimum suite) a best error below `-1e-6` (beating the optimum is impossible if correct); or (full protocol only) a mean `> 1e6 ×` a non-trivial reference mean. | Open `summary\verification.json` → `failures` for the exact (function, dimension) and reason. Non-finite/sign failures indicate a real bug. A gross-deviation failure under a short/over-budget run is expected; `gsk_validate --verify <run_dir> benchmarks\cec_reference_results` reads the protocol from the run's `summary\environment.json` (pass `--reduced` to force the reduced-budget context). |
| Verdict `CONSISTENT` but win/tie/loss all 0 and `missing_reference` > 0 | No published reference table for that optimizer/suite/dimension (e.g. `gsk` on CEC2013 D20 or CEC2013LSGO; any optimizer except `agsk` and `dt-gsk` on CEC2020). | Nothing to fix — there is simply nothing to compare against. The run is still valid. |
| eGSK `egsk:fminconUnavailable` | The Optimization Toolbox / `fmincon` is not available for the reference-mode IP stage. | Install/enable Optimization Toolbox, or run a lower-level explicit diagnostic with `options.use_fmincon=false` knowing it will not match the reference IP behavior. |
| `dt_gsk_optimize:options` ... `DT-GSK draws from Threefry substreams only; got rand_generator '...'` (or `options.seed is required`) | A lower-level `dt_gsk_optimize` call passed a generator other than `threefry` (or no seed). The runner never triggers it: it always hands DT-GSK `threefry`. | Pass `'rand_generator','threefry'` (empty, `auto` and `default` are also accepted) and a seed ([3.7](#37-dt-gsk)). |
| DT-GSK ignores the unified `X0`; its seed/generator do not follow `--seed-policy` / `--rand-generator` | Expected: DT-GSK is unified-only (`get_cec_seed` + `threefry` under every policy) and samples its own `NP = 5*D` population (documented fair-start exception, recorded as `initial_population_policy`). | Nothing to fix. Do not count DT-GSK in a claim that all optimizers started from the same `X0`; it does share their seeds ([3.7](#37-dt-gsk)). |
| `compare_reference_runs:toolbox` | `ranksum` is missing: the Statistics and Machine Learning Toolbox is not installed. | Install/enable the toolbox, or use the toolbox-free `analyze_results` / `gsk_validate --compare` instead. |
| FDB-AGSK empty `KW_ind` / index issues in old reduced-budget traces | Original reference flow assumed `np_init < 0.1*max_nfes`; this port guards the phase condition, but very large opt-in populations still reduce generation count sharply. | Use a larger `max_nfes` or a smaller `options.np_init` (default 100) for quick checks. |
| `gsk_run: suite S has fixed per-function dimensions; omit dimensions or use 0.` | A nonzero dimension was given for a native-dimension suite (cec2011, cec2013lsgo); the native value itself (e.g. 1000) is rejected too. | Use `--dimension 0` (or omit dimensions / set `[0]`). (2.8) |
| `gsk_run: dimension D is not part of suite S.` | D is not a supported dimension of a fixed-dimension-list suite (cec2013, cec2017, cec2020); `0` is not accepted there. | Pick a listed dimension from `build\gsk_list.exe --benchmarks`, or omit dimensions to run all of them. (2.8) |
| `gsk_run: function N is not part of suite ...` | Requested a function outside the suite's range. | Check ranges with `build\gsk_list.exe --benchmarks` (2.8). Note CEC2017 F2 is valid but excluded from default comparisons. |
| `Config error <file>:<line>: unknown key '...'` (or `parallel ... not implemented`, or `data_root is not supported`) | A typo'd or unsupported config key; `parallel: true`; or a `data_root` key (benchmark data always loads from `<root>\benchmarks\cec_suite_cpp\<suite>\input_data`). | Use only the documented keys (2.7 / [configuration.md](configuration.md) / `configs/README.md`). Runs are sequential — only `parallel: false` is accepted. Remove any `data_root` line. |
| `gsk_run: --function expects one integer, got '1,3'` (also `--dimension`, `--runs`, `--max-evaluations`, `--seed`) | Each numeric flag takes one whole integer; comma lists, fractions and trailing text are rejected (exit 2). | Repeat the flag for several values (`--function 1 --function 3`); `--seed` must be in `[0, 2^53]` and `--max-evaluations` `>= 0`. |
| `ctest` reports a failed test | The C++ build/toolchain is broken (not your experiment). | Re-run the build (2.4); fix the compiler/CMake before running any optimizer. Use `ctest --test-dir build --output-on-failure` for detail. |
| `gsk_validate: no summary tables found under <root>` | `--compare`/`--verify` pointed at a path without the CEC summary layout. | Point at the results root (e.g. `results`) or a run dir containing `summary\<opt>_<suite>_D<dim>.csv` (2.9). |

General: run any tool with no arguments (or `--help`) to print its exact usage —
`build\gsk_run.exe --help`, `build\gsk_validate.exe`, `build\gsk_list.exe`.

---

## 6. Quick command reference

| Task | Command |
|---|---|
| Locate your tools | `(Get-Command cmake).Source` · `(Get-Command g++).Source` · `(Get-Command matlab).Source` |
| Build the C++ CLIs | `cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release` then `cmake --build build -j` |
| Run the C++ port tests | `ctest --test-dir build --output-on-failure` |
| Build the MEX bridge | `powershell -File scripts\build_mex_bridge.ps1` |
| List suites / optimizers / references | `build\gsk_list.exe --benchmarks` · `--optimizers` · `--references benchmarks\cec_reference_results` |
| Smoke-test a suite (no optimizer) | `build\gsk_validate.exe --suite cec2017 --smoke` |
| Preview the MATLAB command (no run) | `build\gsk_run.exe --config configs\smoke.yml --root . --dry-run` |
| Tiny end-to-end run (gsk) | `build\gsk_run.exe --config configs\smoke.yml --root .` |
| Run one optimizer, explicit flags | `build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 --function 1 --runs 3 --seed 20240620 --seed-policy reference --overwrite` |
| Run with MATLAB off PATH | add `--matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"` |
| Override the budget (iterations) | add `--max-evaluations 50000` (CLI) / `'max_nfes',50000` (runner) / `max_evaluations: 50000` (config) |
| Native-dim suite (cec2011) | `build\gsk_run.exe --optimizer gsk --suite cec2011 --dimension 0 --runs 3 --seed 20240620 --max-evaluations 150000 --overwrite` |
| Full CEC2017 matrix (7 optimizers) | `build\gsk_run.exe --config configs\all_cec2017.yml --root .` |
| Full CEC2011 matrix (7 optimizers) | `build\gsk_run.exe --config configs\all_cec2011.yml --root .` |
| AGSK on CEC2020 | `build\gsk_run.exe --config configs\agsk_cec2020.yml --root .` |
| DT-GSK full CEC2017 campaign | `build\gsk_run.exe --optimizer dt-gsk --suite cec2017 --runs 51 --seed 20240620` |
| Per-run comparison vs an imported campaign (Statistics Toolbox) | MATLAB: `compare_reference_runs('results/dt-gsk/cec2017','benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv')` (from the project root with `scripts` on the path) |
| MATLAB IDE: high-level run | `cd src/runners` then `run_experiment('optimizer','gsk','suite','cec2017','functions',[1 3],'dimensions',[10],'runs',3,'base_seed',20240620,'max_nfes',0,'project_root','<root>','output_dir','<root>/results/gsk/cec2017','overwrite',true)` |
| MATLAB IDE: low-level run (custom options) | `problem = gskcec_make_problem('cec2017',1,10,'<root>',50000); result = gsk_optimize(problem, struct('seed',777,'np',100));` |
| Compare all results vs references | `build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv` |
| Re-verify one run dir | `build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results` (protocol read from `summary\environment.json`; `--reduced` / `--full` override it) |
| Skip auto-verification on a run | add `--no-verify` to `gsk_run` |
| Stats + figures (toolbox-free) | MATLAB: `analyze_results('project_root','<root>','results_root','<root>/results','reference_root','<root>/benchmarks/cec_reference_results','output_dir','<root>/results/analysis')` (archives ignored; references matched to the exact dimension; duplicate `gsk_run` / launcher layouts are labeled by path with a warning, so use `results_root = <root>/results/_run_all` or `<root>/results/<opt>` to pick one layout) |
| MATLAB-only smoke tests (no MEX) | `matlab -batch "cd('src/tests'); run_matlab_smoke_tests"` |
