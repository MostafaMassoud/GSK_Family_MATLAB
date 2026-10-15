# Tutorial: build, test, and run your first experiment

> **What this is:** a single end-to-end walkthrough - build the C++ tooling, run
> the tests, validate a suite, run one tiny experiment, read every output file,
> and interpret the CONSISTENT/DEVIATES verdict. **For:** a newcomer who wants
> one guided first run. **Prerequisites:** CMake and a C++20 compiler for steps
> 1-3; MATLAB R2025b additionally for step 4 (the optimizer run). New to the
> ideas? Read [explainer.md](explainer.md) first. **After reading:** you will
> have produced and understood a complete result tree and be ready for
> [user_guide.md](user_guide.md) and [command_reference.md](command_reference.md).

This is a single end-to-end walkthrough for a newcomer. By the end you will
have:

1. built the C++ tooling,
2. run the C++ unit tests (which prove the benchmark ports are correct),
3. validated a benchmark suite (`gsk_validate --suite cec2017 --smoke`),
4. run a tiny experiment (`gsk_run --config configs/smoke.yml`),
5. read every output file it produced, and
6. understood the **CONSISTENT** vs **DEVIATES** verdict and how to compare
   against the published reference tables.

If a term is unfamiliar, see the [glossary](../reference/glossary.md); for the
concepts, read [explainer.md](explainer.md) first.

Throughout, the project root is the folder that contains `CMakeLists.txt` and
`README.md`. Commands are shown for **PowerShell** on Windows (the project's
development platform). Run them from the project root unless told otherwise.

> **A note on the two halves.** Steps 1–3 are pure **C++** and need only CMake
> and a C++20 compiler. Step 4 actually runs a **MATLAB** optimizer against the
> C++ benchmark, so it additionally needs MATLAB and the one-time MEX-bridge
> build. If you do not have MATLAB, you can still do steps 1–3 and the
> `--dry-run` part of step 4.

---

## 0. Prerequisites

| Tool | Needed for | Version |
|---|---|---|
| **CMake** | configuring/building the C++ tooling | ≥ 3.20 |
| **A C++20 compiler** | compiling the benchmarks, library, CLIs, tests | e.g. GCC 16.x |
| **MATLAB** *(optional)* | running the GSK optimizers in step 4 | R2025b used by the project |

This project is developed with the **WinLibs MinGW-w64** GCC toolchain plus the
"MinGW Makefiles" CMake generator. Two practical ways to get the tools:

- Install **WinLibs MinGW-w64** (it bundles `g++`, and 4.x ships `cmake` too).
  The project was built with the winget package
  `BrechtSanders.WinLibs.POSIX.UCRT`.
- Or reuse the **CMake that ships inside MATLAB**, at
  `<matlabroot>\bin\win64\cmake\bin\cmake.exe` (for example
  `C:\Program Files\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe`).

**Pointing at your tools.** The instructions below call `cmake`, `g++`, and
`matlab` by bare name, which works if they are on your `PATH`. If they are not,
use full paths instead — for example
`& "C:\path\to\mingw64\bin\cmake.exe" ...` and pass the compiler explicitly with
`-DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"`. Do **not** copy any one
user's absolute paths; substitute your own. To check what is on your PATH:

```powershell
(Get-Command cmake).Source
(Get-Command g++).Source
(Get-Command matlab).Source   # only if you plan to do step 4
```

---

## 1. Build the C++ tooling

From the project root:

```powershell
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

- `-S .` is the source directory (the project root), `-B build` is the build
  directory (created for you; it is gitignored).
- `-j` builds in parallel.

Rebuild this C++ tree whenever you change C++ headers or sources, CEC suite
ports, CLI/config/parser code, tests, or `CMakeLists.txt`. The generated
executables under `build\` are not refreshed until you rerun
`cmake --build build -j`.

If `cmake`/`g++` are not on PATH, the equivalent with explicit paths is:

```powershell
& "C:\path\to\mingw64\bin\cmake.exe" -S . -B build -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"
& "C:\path\to\mingw64\bin\cmake.exe" --build build -j
```

When it finishes, the build directory contains four command-line tools plus the
test executables and the static library:

```text
build\gsk_list.exe        enumerate suites, optimizers, reference tables
build\gsk_validate.exe    validate ports / smoke-test suites / compare results
build\gsk_run.exe         run an experiment (drives MATLAB) and auto-verify it
build\gsk_bench.exe       micro-benchmark the C++ port evaluate() throughput (no MATLAB)
build\libgskcec.a         the C++ support library
build\gskcec_*_tests.exe  the C++ unit tests (run via ctest, step 2)
```

The three tools used in this tutorial are `gsk_list`, `gsk_validate`, and
`gsk_run`; `gsk_bench` is a timing tool covered in
[performance.md](../research/performance.md).

Sanity-check the build by listing what the toolkit knows about. These commands
do not need MATLAB:

```powershell
build\gsk_list.exe --benchmarks
build\gsk_list.exe --optimizers
```

Expected output (abridged):

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

These are the seven GSK-family optimizers; the first six are ports of MATLAB
reference releases, and `dt-gsk` is a port of the DT-GSK reference
implementation.

You can also summarize the imported published result tables you will later
compare against:

```powershell
build\gsk_list.exe --references benchmarks\cec_reference_results
```

This prints one line per reference file and a final `files=` / `rows=` total.

---

## 2. Run the C++ tests (proof the ports are correct)

The C++ unit tests compare each benchmark port against fixed ground-truth values
produced by the **original** reference implementations. Passing them means the
re-implemented functions return the same numbers as the originals, bit-for-bit
(to a tiny tolerance). Run them with **CTest**, which ships with CMake:

```powershell
ctest --test-dir build --output-on-failure
```

If `ctest` is not on PATH, use the same directory as your `cmake`, e.g.
`& "C:\path\to\mingw64\bin\ctest.exe" --test-dir build --output-on-failure`.
For a verbose run that prints each suite's own summary line, add `-V`.

Expected result: every test reports `Passed`. The test set covers the core
utilities, the reference-table loader, the experiment tooling, the CEC2011 work
packages plus integration, and one suite per CEC benchmark (with a couple of
additional tooling smoke tests). A healthy tail looks like:

```text
100% tests passed, 0 tests failed out of <N>
```

where `<N>` is the number of registered test executables in your build. If any
test fails, stop here — the build or toolchain is the problem, not your
experiment.

---

## 3. Validate a suite: `gsk_validate --suite cec2017 --smoke`

A **smoke test** quickly checks that every function in a suite can be
constructed and evaluated and returns a sensible (finite) number at two in-bounds
probe points. It does **not** run any optimizer; it is a fast health check of the
benchmark ports and their input data.

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
```

Expected output (the elapsed time will vary by machine):

```text
Suite cec2017 smoke passed: 120 (function,dimension) cells evaluated in 0.56 s.
```

(120 = 30 functions × 4 dimensions for CEC2017.) The same works for the other
suites — exactly these five names are valid: `cec2011`, `cec2013`,
`cec2013lsgo`, `cec2017`, `cec2020`:

```powershell
build\gsk_validate.exe --suite cec2020 --smoke
build\gsk_validate.exe --suite cec2013 --smoke
build\gsk_validate.exe --suite cec2013lsgo --smoke
build\gsk_validate.exe --suite cec2011 --smoke
```

Two suite-specific notes you will actually see:

- **CEC2020** legitimately lacks reference data for a few (function, dimension)
  cells; the smoke test prints them as explicit `SKIP …` lines rather than
  failing or hiding them.
- **CEC2013** has no runnable reference implementation locally, so it also offers
  a saved-vector regression check:
  `build\gsk_validate.exe --suite cec2013 --against saved_vectors`.

Run `build\gsk_validate.exe` with no arguments at any time to see the exact
usage:

```text
Usage:
  gsk_validate --references <cec_reference_results_root>
  gsk_validate --suite <name> --smoke [--root <project_root>]
  gsk_validate --suite cec2013 --against saved_vectors [--root <project_root>]
  gsk_validate --compare <results_root> <cec_reference_results_root> [--out <report.csv>]
  gsk_validate --verify <run_dir> <cec_reference_results_root> [--reduced|--full]
      (without --reduced/--full the protocol is read from the run's
       summary/environment.json runs/max_nfes_override; full if absent)
```

(`--root` defaults to the current directory; pass it if you run from elsewhere.)

---

## 4. Run a tiny experiment: `gsk_run --config configs/smoke.yml`

Now we run an actual GSK optimizer against a real benchmark. The smoke config is
deliberately minimal — one optimizer, one function, a tiny budget — so it
finishes in seconds.

`configs/smoke.yml`:

```yaml
# Quick end-to-end smoke: one optimizer, one function, tiny budget.
# Run with: gsk_run --config configs/smoke.yml --root .
optimizers: [gsk]
suite: cec2017
dimensions: [10]
functions: [1]
runs: 1
seed: 20240620
seed_policy: reference
rand_generator: threefry
max_evaluations: 2000
overwrite: true
```

The config keys are a strict flat-YAML subset (unknown keys are rejected with a
line number). The accepted keys are: `optimizers`, `suite`, `functions`,
`dimensions`, `runs`, `seed`, `seed_policy`, `rand_generator`,
`max_evaluations`, `output_root`, `reference_root`, `overwrite`, and `parallel`
(only `parallel: false` is accepted; `true` is rejected on purpose, since this
version runs sequentially). A `data_root` key is rejected: benchmark data always
loads from `<root>\benchmarks\cec_suite_cpp\<suite>\input_data`.

### 4a. One-time MEX-bridge build (needs MATLAB)

`gsk_run` drives MATLAB, and the MATLAB optimizers evaluate the C++ benchmarks
through the optional `gskcec_eval` **MEX** bridge. Build it once:

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This produces `build\mex\gskcec_eval.mexw64`. (It needs MATLAB and the same
MinGW toolchain. The benchmark *library* and steps 1–3 never require this — only
running optimizers from MATLAB does.)

Rebuild this bridge after changes to CEC suite source files or
`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/`. MATLAB CEC experiments call
`build\mex\gskcec_eval.<mexext>`, so rebuilding only the C++ CLIs is not enough
after MEX-relevant changes.

### 4b. Preview without running: `--dry-run`

Before running for real, you can print the exact MATLAB command `gsk_run` would
execute. This needs neither MATLAB nor the MEX bridge:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root . --dry-run
```

Expected output (paths will reflect your own location):

```text
gsk_run: [smoke] gsk on cec2017 -> ./results/gsk/cec2017
DRY-RUN: "matlab" -batch "cd('./src/runners'); run_experiment('optimizer','gsk',
  'suite','cec2017','functions',[1],'dimensions',[10],'runs',1,'base_seed',20240620,
  'max_nfes',2000,'project_root','<...>','output_dir','<...>/results/gsk/cec2017',
  'overwrite',true,'seed_policy','reference','rand_generator','threefry',
  'use_parallel',false);"
```

This shows precisely how the C++ orchestrator hands the request to the MATLAB
runner — useful for understanding and for debugging.

The C++ command passes the seed/RNG policy documented in
[seed_policy.md](../reference/seed_policy.md): default `seed_policy='reference'`,
default requested `rand_generator='threefry'`, and `use_parallel=false`.
Reference mode records the effective generator in metadata; AGSK, APGSK,
FDB-AGSK, eGSK, and ATMALS-GSK use legacy `seed`, while GSK uses `twister`.
(DT-GSK is the exception: it always runs the unified seed with `threefry`,
under every policy; see [command_reference.md](command_reference.md#37-dt-gsk).)
For new fair cross-family experiments, choose `seed_policy='unified'`; it uses
one optimizer-independent seed schedule over `(D,function,run)`, shares the
runner-generated initial population and post-initialization RNG state, and
uses `threefry` when MATLAB supports it, otherwise `twister`.
The unified formula is:

```text
seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
```

Only the base seed, dimension, function, and run appear in that formula. This is
what makes a fair cross-family run different from a reference-reproduction run:
the algorithm name, algorithm order, population size, and budget cannot move the
seed. With the default base seed, `(D=30, F=7, run=12)` gives `69241386` for
every optimizer.

### 4c. Run it for real

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

What happens, in order:

1. `gsk_run` validates the request against the C++ benchmark factory (is
   function 1 part of CEC2017? is dimension 10 supported? — yes).
2. It launches MATLAB in `-batch` mode to run `src/runners/run_experiment.m`,
   which executes the `gsk` optimizer once (`runs: 1`) on CEC2017 function 1 at
   `D=10` with a 2000-evaluation budget, and writes the result files.
3. It then **automatically verifies** the run against the `gsk` published
   reference table and writes `verification.json` or the next available
   `verification_<n>.json` file if a previous verdict is already present.

Because the budget is tiny (2000) and there is only 1 run, this is a **reduced
protocol** run (the threshold is `< 25` runs, or any overridden budget). The
verification therefore treats the win/tie/loss tally and gross-deviation check as
*informational* — a 2000-evaluation run is legitimately worse than a full
`10000 × D = 100000`-evaluation published run, and that is not a bug.

**Where MATLAB is found:** by `--matlab <exe>`, else the `GSKCEC_MATLAB`
environment variable, else `matlab` on PATH. If MATLAB is not on your PATH, run:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root . `
    --matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"
```

You can also bypass the config entirely and pass flags directly:

```powershell
build\gsk_run.exe --optimizer gsk --suite cec2017 --dimension 10 `
    --function 1 --runs 3 --seed 20240620
```

(Run `build\gsk_run.exe --help` to see every flag, including `--seed-policy`,
`--rand-generator`, `--overwrite` clean-run mode, `--output`,
`--reference`, and `--no-verify`.)

---

## 5. Read the output files

The run writes one tree per `(optimizer, suite)` in the CEC-competition layout
`results/<optimizer>/<suite>/`. For the smoke config that is:

```text
results\gsk\cec2017\
  summary\
    gsk_cec2017_D10.csv     statistics table: Function,Best,Median,Mean,Worst,SD
    seed_schedule.csv       deterministic seeds for every function/dimension/run
    per_run.csv             one row per individual run (seeds, nfes, termination)
    environment.json        provenance + metadata for the whole run
    verification.json       the CONSISTENT / DEVIATES verdict
  curves\
    Figure_F1_D10_Run#1.csv the median run's convergence trace (Eval,BestError,Log10Error)
  gen_logs\
    CheckpointErrors_gsk_F1_D10.csv  per-run error at the CEC checkpoints
```

Re-running an `(optimizer, suite)` preserves the existing tree. Completed run
ids are skipped, missing runs are appended, and fixed-name refreshed artifacts
are archived under `_archive\<timestamp>\`. The imported reference tables under
`benchmarks\cec_reference_results` are never written to (`run_experiment`
refuses an output folder there). Full column definitions live in
[result_schema.md](../reference/result_schema.md); here is how to *read* each
file.
The resume logic is seed-, budget- and generator-aware: if a previous
`per_run.csv` row was produced with another seed, budget (`max_nfes`) or
generator, it remains on disk for audit history but does not satisfy the
current run, which is redone and appended.

### summary\gsk_cec2017_D10.csv — statistics table (per dimension)

Columns — the **same six-column schema as the published reference tables**, so
generated and reference results are directly comparable:

```text
Function,Best,Median,Mean,Worst,SD
```

One row per function at that dimension. `Best`/`Median`/`Mean`/`Worst`/`SD`
summarize the **errors** when the suite has a known optimum (CEC2017 does), or
the **raw scores** otherwise. With a single run these five numbers are all equal.
`SD` is the sample standard deviation. Which basis was used is recorded as
`statistics_basis` in `environment.json`. For CEC2017 the optimum of function 1
is `100 × 1 = 100`, so the error is `best_fitness − 100`. Native-dimension suites
(CEC2011, CEC2013LSGO) also get a dimensionless rollup `gsk_cec2011.csv`.

### summary\per_run.csv — one row per individual run

Columns:

```text
optimizer,suite,function,dimension,run,seed,best_fitness,error,nfes,termination,runtime_seconds,max_nfes,rand_generator
```

- `best_fitness` — the lowest raw score the optimizer found (stored with
  `%.17g`, full round-trip precision).
- `error` — `best_fitness − optimum`, with errors below `1e-8` zeroed exactly as
  the reference drivers do. (On CEC2011, which has no published optimum,
  `error` is `NaN`; on CEC2013LSGO the optimum is `0`, so `error` equals the raw
  `best_fitness`.)
- `nfes` — the number of function evaluations actually consumed (here ≈ 2000).
- `seed` — the deterministic per-run seed.
- `termination` — for baseline GSK this is always `max_evaluations`.
- `max_nfes` — the cell's evaluation budget (here 2000, after the override).
- `rand_generator` — the generator the run actually used (under the reference
  policy GSK uses `twister`).

A rerun into the same folder reuses a row only when its `seed`, `max_nfes` and
`rand_generator` all match the new run; otherwise that run is redone and a
fresh row is appended.

Under unified mode, the same `(dimension,function,run)` key must show the same
seed for every optimizer. The `seed_schedule.csv` file is the fastest place to
audit that property.

### curves\Figure_F1_D10_Run#1.csv — the convergence curve

Columns `Eval,BestError,Log10Error` for the **median run** of each
(function, dimension): the best-so-far error after each generation versus
evaluations spent. Plotting `BestError` against `Eval` gives the convergence
curve described in [explainer.md](explainer.md) §5. (`Log10Error` is blank where
the value is non-positive.) Open it in MATLAB, a spreadsheet, or any other tool.

### gen_logs\CheckpointErrors_gsk_F1_D10.csv — checkpoint table

One row per run (`Run,Seed,E<nfes>...`): the best-so-far error at the standard
CEC evaluation checkpoints (`[0.01 … 1.0] × max_nfes`). This is the per-run
table used for CEC-style reporting.

### summary\environment.json — how to reproduce or audit this run

Human- and machine-readable provenance: the MATLAB `command`, the
`optimizer`/`suite`/`functions`/`dimensions_run`/`runs`, the
`base_seed`, `seed_policy`, `initial_population_policy`, `max_nfes_override`,
the `statistics_basis`, the `checkpoint_fractions`, the data/reference/output roots, `matlab_version`,
`cpu_cores`, `computer`/`platform`, `timestamp`, `git_commit` (when available),
total runtime, any `skipped_cells`, and `optimizer_notes`. If you ever need to
regenerate this result, the `command` field is the recipe.

### verification.json — the CONSISTENT / DEVIATES verdict

This is written automatically by `gsk_run`; repeated checks use
`verification_1.json`, `verification_2.json`, and so on rather than replacing a
previous verdict. Example shape (your numbers will differ):

```json
{
  "optimizer": "gsk", "suite": "cec2017", "verdict": "CONSISTENT",
  "reduced_budget": true, "functions_checked": 1, "hard_failures": 0,
  "win_tie_loss": [0, 0, 1], "missing_reference": 0,
  "thresholds": { "negative_error_floor": -1e-06, "gross_factor": 1e06,
                  "reference_trivial_floor": 1e-08 },
  "failures": []
}
```

How to read it — see §6.

---

## 6. Interpret CONSISTENT vs DEVIATES

The verdict answers: *does this run behave consistently with the same
optimizer's published reference table?* It is built to catch **implementation
bugs**, not to grade optimization quality. The verdict is `DEVIATES` only if a
**hard-failure** check fires; otherwise it is `CONSISTENT`.

The hard-failure checks are:

1. **Non-finite statistics** — any `NaN`/`Inf` in the summary means something is
   broken.
2. **Impossible negative error** (known-optimum suites only) — a best error below
   `negative_error_floor` (`-1e-6`) would mean the optimizer "beat" the true
   optimum, which is impossible if the port and optimizer are correct.
3. **Gross deviation** (full protocol only) — a mean more than `gross_factor`
   (`1e6`) times a non-trivial reference mean signals a gross bug. This check is
   **skipped under a reduced protocol**, because a short run is legitimately
   worse than the published table.

So:

- **CONSISTENT** — no hard-failure check fired. For the smoke run (reduced
  budget) this is the expected outcome even though the tiny-budget result is far
  from the published full-budget result. The `win_tie_loss` tally there is
  informational.
- **DEVIATES** — at least one hard-failure check fired. `gsk_run` also **exits
  with a nonzero status** so scripts/CI notice. Inspect the `failures` list in
  `verification.json` (and the console lines `gsk_run` prints) to see exactly
  which (function, dimension) and which check.

`reduced_budget: true` in the JSON tells you the run used an overridden budget or
fewer than 25 runs, which is why the magnitude check and win/tie/loss are
informational here.

### Re-checking a run later

You can re-run the verdict on any existing run directory without re-running the
optimizer:

```powershell
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results
```

Without `--reduced` / `--full`, `--verify` reads `runs` and `max_nfes_override`
from the run's `summary\environment.json` (the same rule `gsk_run` uses; the
full protocol when that file is absent), so this smoke run is again judged as
reduced budget. Pass `--reduced` or `--full` only to override that; `--full`
applies the strict context, where the gross-deviation check becomes a hard
failure. `--verify` writes the next available `verification*.json` file and
exits nonzero on `DEVIATES`.

### Opting out of verification

If you deliberately do not want the automatic check (e.g. an exploratory run),
pass `--no-verify` to `gsk_run`. The result files are still written; only
`verification.json` is skipped.

---

## 7. Compare results against the published references

Verification is a per-run pass/fail. To *see the numbers side by side* against
the published reference tables, use `--compare`:

```powershell
build\gsk_validate.exe --compare results benchmarks\cec_reference_results --out results\comparison.csv
```

This walks every per-dimension summary table
(`<optimizer>/<suite>/summary/<optimizer>_<suite>_D<dim>.csv`) under `results\`,
matches each to the corresponding published table by (suite, algorithm,
dimension), and prints one line per comparable (function, dimension):

```text
gsk cec2017 f1 D10 mean=<your mean> ref_mean=<published mean> rel_diff=<...> -> <win|tie|loss>
...
compared=<N> win=<...> tie=<...> loss=<...> no_reference=<...>
```

Lower mean is better; a "tie" is within relative `1e-8`. With `--out` it also
writes the full table to a CSV you can open in a spreadsheet. For the tiny smoke
run you will typically see a `loss` versus the full-budget published table — that
is expected and not an error, for the same reduced-budget reason as above.

---

## 8. What to try next

- **A fuller matrix.** The repository ships ready-made configs:
  `configs\all_cec2017.yml` (all seven optimizers, CEC2017, 51 runs),
  `configs\all_cec2011.yml` (all seven, CEC2011, 25 runs), and
  `configs\agsk_cec2020.yml` (AGSK on CEC2020, 30 runs). These are full
  reproductions and take much longer to run. Example:
  ```powershell
  build\gsk_run.exe --config configs\agsk_cec2020.yml --root .
  ```
- **DT-GSK.** The seventh optimizer runs on any of the five suites with
  `--optimizer dt-gsk` (it has reference tables on all of them).
  [Command Reference section 3.7](command_reference.md#37-dt-gsk) covers its seeding exception and
  the run-by-run comparison with `scripts/compare_reference_runs.m`.
- **MATLAB-only smoke tests.** To exercise the optimizers and runner without the
  MEX bridge (pure-MATLAB sphere problems), run:
  ```powershell
  matlab -batch "cd('src/tests'); run_matlab_smoke_tests"
  ```
- **Read one optimizer and one benchmark.** Open
  `src\optimizers\gsk\gsk_optimize.m` (the algorithm) and
  `benchmarks\cec_suite_cpp\cec2017\src\cec2017_problem.cpp` (a benchmark port);
  both cite their exact reference sources in the header. The
  [code reading guide](../development/code_reading_guide.md) is the map.
- **Browse the C++ API** with Doxygen — see [api.md](../reference/api.md).

Every command above was cross-checked against the actual CLI sources
(`benchmarks/cec_suite_cpp/cec_tools/src/cli/{gsk_list,gsk_validate,gsk_run}.cpp`) and the
shipped configs. If a flag is not listed here, run the tool with `--help` (or no
arguments) to see its built-in usage.
