# Troubleshooting

> **What this is:** fixes for the problems newcomers hit most with the
> `gsk_family` MATLAB + C++ project: the MEX bridge, benchmark data, output
> paths, reference mismatches, the eGSK toolbox requirement, and
> parallel-vs-serial determinism.
> **For:** anyone whose run did not behave as [tutorial.md](tutorial.md),
> [user_guide.md](user_guide.md), [RUNBOOK.md](../../../RUNBOOK.md), or
> [command_reference.md](command_reference.md) describes.
> **Prerequisites:** none. Terms used here are defined in
> [glossary.md](../reference/glossary.md).
> **After reading:** you will be able to diagnose and resolve the common
> failures, and know which reference page to consult for the rest.

Find your symptom in the table, then jump to the section.

| Symptom | Section |
|---|---|
| `gskcec:mexMissing` / `gskcec:mexNotLoadable` / runner stops at startup | [The MEX bridge cannot be found](#the-mex-bridge-cannot-be-found) |
| `gsk_run`: MATLAB invocation failed | [MATLAB cannot be found](#matlab-cannot-be-found) |
| Benchmark data fails to load | [Benchmark data cannot be loaded](#benchmark-data-cannot-be-loaded) |
| Output path rejected (`run_experiment:outputUnsafe`) | [The output root is rejected](#the-output-root-is-rejected) |
| `seed_policy must be reference, unified, native, or derived` / `rand_generator 'auto' is resolved only under seed_policy='unified'` | [A seed policy or generator is rejected](#a-seed-policy-or-generator-is-rejected) |
| `verify_unified_seed_schedule:missingKeys` warning | [The seed-schedule verifier warns about missing keys](#the-seed-schedule-verifier-warns-about-missing-keys) |
| Verdict `DEVIATES` / nonzero exit | [Reference comparison reports DEVIATES](#reference-comparison-reports-deviates) |
| `CONSISTENT` but win/tie/loss all 0 | [CONSISTENT with no comparison](#consistent-with-no-comparison) |
| eGSK `egsk:fminconUnavailable` | [eGSK requires the Optimization Toolbox](#egsk-requires-the-optimization-toolbox) |
| `dt_gsk_optimize:options` (`DT-GSK draws from Threefry substreams only`) | [DT-GSK rejects the generator](#dt-gsk-rejects-the-generator) |
| DT-GSK ignores the runner `X0` / the seed policy | [DT-GSK ignores X0 and the seed policy](#dt-gsk-ignores-x0-and-the-seed-policy) |
| `compare_reference_runs:toolbox` | [The per-run comparison needs the Statistics Toolbox](#the-per-run-comparison-needs-the-statistics-toolbox) |
| Parallel and serial disagree | [Parallel and serial results differ](#parallel-and-serial-results-differ) |
| First run slow / pool warmup | [First run is slow](#first-run-is-slow) |
| `cmake` / `g++` / `matlab` not found | [A build tool is not on PATH](#a-build-tool-is-not-on-path) |
| `gsk_run: dimension ...` / `suite ... has fixed per-function dimensions` / `function ...` rejected | [A function or dimension is rejected](#a-function-or-dimension-is-rejected) |
| `gsk_run: --function expects one integer, got ...` | [A command-line value is rejected](#a-command-line-value-is-rejected) |
| `Config error <file>:<line>: unknown key` / `data_root is not supported` | [A config key is rejected](#a-config-key-is-rejected) |

## The MEX Bridge Cannot Be Found

MATLAB CEC experiments evaluate the C++ benchmarks through the `gskcec_eval` MEX
bridge. If `build\mex\gskcec_eval.mexw64` was never built or is missing, the
runner raises `gskcec:mexMissing` (or `gskcec:mexMissingPrerequisite`). The root
`run_all_cec*.m` launchers and `run_experiment` stop at startup for this global
prerequisite, on purpose, so they do not write a partial, all-skipped result
tree.

Build it once (needs MATLAB plus the MinGW toolchain):

```powershell
powershell -File scripts\build_mex_bridge.ps1
```

This produces `build\mex\gskcec_eval.mexw64`. The runner adds `build\mex` to the
MATLAB path automatically. If you use the lower-level `gskcec_make_problem` path
directly, add it yourself first: `addpath('<root>/build/mex')`. The bridge is a
separate binary from the C++ CLIs, so `cmake --build build -j` does **not**
refresh it - rebuild the bridge after any change to CEC suite sources or
`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge/`. The pure-MATLAB `sphere` smoke
tests need no bridge.

**The bridge exists but cannot be loaded (`gskcec:mexNotLoadable`).** The
startup gate (`gskcec_require_mex`) does not only check that the file exists; it
forces a real load (a bare `gskcec_eval()` call that creates no handle). A bridge
that exists but cannot load therefore fails at startup instead of turning every
cell into a `SKIP`. The usual cause is a bridge built by the old script: it
imports `libwinpthread-1.dll` and fails with `Invalid MEX-file ... The specified
module could not be found.` when no MinGW `bin` folder is on `PATH`. Rebuild
with `scripts\build_mex_bridge.ps1`, which now links `-static` and needs no
MinGW runtime DLL at load time. If the build script reports that it could not
replace the file, the bridge is still loaded: run `gskcec_eval('clear'); clear
mex` in that MATLAB session (live problem handles keep the bridge locked in
memory) or close MATLAB, then retry.

## MATLAB Cannot Be Found

`gsk_run` prints `MATLAB invocation failed` (or cannot locate MATLAB) when MATLAB
is not on `PATH` and neither `--matlab` nor the `GSKCEC_MATLAB` environment
variable is set. It looks in this order: `--matlab <exe>`, then `GSKCEC_MATLAB`,
then `matlab` on `PATH`. Pick one:

```powershell
# (a) pass it per-invocation
build\gsk_run.exe --config configs\smoke.yml --root . `
    --matlab "C:\path\to\MATLAB\R2025b\bin\matlab.exe"

# (b) set the env var (the MEX builder reads it too)
$env:GSKCEC_MATLAB = "C:\path\to\MATLAB\R2025b\bin\matlab.exe"

# (c) add MATLAB to PATH for this shell
$env:Path = "C:\path\to\MATLAB\R2025b\bin;$env:Path"
```

For the MATLAB IDE path you simply launch MATLAB and run `run_experiment(...)` in
its Command Window - no `PATH` setup needed there. To confirm the request
without launching MATLAB at all, add `--dry-run`; it prints the exact MATLAB
`-batch` command and needs neither MATLAB nor the bridge.

## Benchmark Data Cannot Be Loaded

The runner could not find the benchmark input-data files. There is no
`data_root` setting to check: data always loads from
`<root>\benchmarks\cec_suite_cpp\<suite>\input_data`, where `<root>` is the
project root passed to the runner, and a config `data_root` key is rejected.
Check that the input-data folder of that suite exists under:

```text
benchmarks\cec_suite_cpp
```

When using a config, pass the project root explicitly so relative config paths
resolve under the project rather than the working directory:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

`--root` rebases relative `output_root` and `reference_root` from a config under
the project root (explicit `--output` / `--reference` flags resolve against the
working directory). You can confirm a suite's data loads and evaluates to
finite numbers, with no optimizer and no MATLAB, using the smoke check:

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
```

(CEC2020 prints explicit `SKIP ...` lines for the few cells without shuffle data
- functions 1 and 8 at D=5 and D=15 - which is expected, not a failure.)

## The Output Root Is Rejected

This is a safety guard, not a bug. `run_experiment` refuses, with
`run_experiment:outputUnsafe`, any `output_dir` inside (or equal to) the imported
reference tree:

```text
benchmarks\cec_reference_results
```

The check runs on every run (not only with `overwrite`), right after argument
parsing and before any folder is created; a relative `output_dir` is resolved
against the current MATLAB folder first. A `gsk_run` invocation that points
there fails the same way, because it passes the output directory to
`run_experiment`.

Point `output_root` (config) / `--output` (CLI) / `'output_dir'` (runner) at
`results\` or another generated-output directory. Keeping generated output and
read-only reference evidence separate is intentional - the imported tables and
curated benchmark-side curves/logs are never written to by a run. See
[result_schema.md](../reference/result_schema.md) for the full layout.

## Reference Comparison Reports DEVIATES

A run's automatic check writes `summary\verification.json` with verdict
`CONSISTENT` or `DEVIATES`; `gsk_run` exits nonzero on `DEVIATES`. The verdict
catches **implementation bugs**, not optimization quality. It is `DEVIATES` only
when a hard-failure check fires:

1. **Non-finite statistics** - any `NaN`/`Inf` in the summary.
2. **Impossible negative error** (known-optimum suites only) - a best error below
   `-1e-6`, which would mean the optimizer beat the true optimum.
3. **Gross deviation** (full protocol only) - a mean more than `1e6` times a
   non-trivial reference mean.

First, **check the budget**. Reduced-budget runs (an overridden `max_nfes`, or
fewer than 25 runs) are valid smoke tests but are not expected to reproduce full
reference statistics, and the gross-deviation check is skipped for them. A
`DEVIATES` verdict on a short run that fired the magnitude check usually means
"too few evaluations", not "wrong". Re-check the run directory standalone:

```powershell
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results
```

`--reduced` is not required when the run directory has
`summary\environment.json`: `--verify` reads `runs` / `max_nfes_override` from it
(the same rule `gsk_run` uses) and prints `protocol from: <source>`. Without that
file it assumes the full protocol; pass `--reduced` or `--full` to override.

Open `summary\verification.json` -> `failures` for the exact (function,
dimension) and reason. A non-finite or negative-error failure indicates a real
bug; confirm you are also comparing like with like (same suite, function ids,
dimensions, optimizer id, and statistics basis on both sides). The verdict
fields, thresholds, and comparison rules are in
[result_schema.md](../reference/result_schema.md) and
[benchmark_protocol.md](../reference/benchmark_protocol.md).

## CONSISTENT With No Comparison

A verdict of `CONSISTENT` with `win/tie/loss` all `0` and `missing_reference > 0`
is not an error - it means there is no imported reference table for that
optimizer/suite/dimension, so there is nothing to contradict. The shipped tables
cover CEC2017 (all seven optimizers, D10/30/50/100), CEC2011 (all seven
optimizers), CEC2013 (`gsk` and `dt-gsk` at D10/30/50), and CEC2020 (`agsk`
and `dt-gsk`); CEC2013LSGO holds `dt-gsk` (D1000/D905) plus the DECC-G and MOS
baselines. Everything else (for example any optimizer except `dt-gsk` on
CEC2013LSGO, optimizers other than `gsk`/`dt-gsk` on CEC2013, or any optimizer
except `agsk` and `dt-gsk` on CEC2020) reports `missing_reference`, and the
gross-deviation check cannot fire for it (the finiteness and sign checks still
apply). The run is still valid; there is simply nothing to compare against.

## eGSK Requires The Optimization Toolbox

Reference-mode eGSK uses `fmincon` (SQP) for its interior-point local
refinement, gated on
`license('test','Optimization_Toolbox') && exist('fmincon','file')`. With the
toolbox absent, the default eGSK call fails with `egsk:fminconUnavailable`. The
fix is to install or enable the **Optimization Toolbox**. `gsk_run` cannot
disable the IP stage - it always runs the reference-mode path and therefore
requires `fmincon`.

For an explicit, **non-reference diagnostic** only, the lower-level MATLAB path
can skip IP with `options.use_fmincon = false` (it records a note that IP was
disabled and will not match the reference behavior):

```matlab
problem = gskcec_make_problem('cec2017', 1, 10, '<root>', 0);
options = struct('seed', 7, 'np', 100, 'use_fmincon', false);   % non-reference
result  = egsk_optimize(problem, options);
gskcec_eval('free', problem.mex_handle);
```

With the toolbox present, the IP stage's evaluations are counted, so
`result.nfes` can slightly exceed `max_nfes` - that is the reference behavior, not
a fault.

(The other optimizers need no toolbox: ATMALS-GSK replaces the Fuzzy Logic
`gaussmf` with a local `atmals_gaussmf.m`, and the analysis script
`scripts/analyze_results.m` computes Friedman/Wilcoxon and renders figures with
base MATLAB only.)

## DT-GSK Rejects The Generator

`dt_gsk_optimize:options` with `DT-GSK draws from Threefry substreams only; got
rand_generator '...'` comes from a lower-level `dt_gsk_optimize(problem,
options)` call whose `options.rand_generator` is not `threefry` (for example
`twister` or `seed`). DT-GSK derives all of its random numbers from named
Threefry substreams of the run seed, so no other generator is meaningful. Pass
`'rand_generator','threefry'`, or leave it empty / `auto` / `default`. The same
identifier with `options.seed is required` means the seed is missing. Runs
through `run_experiment`, `gsk_run`, or a launcher never hit this: the runner
always hands DT-GSK `threefry`, whatever `rand_generator` was requested.

## DT-GSK Ignores X0 And The Seed Policy

This is expected. DT-GSK is *unified-only*: `run_experiment` gives it the
unified seed `get_cec_seed(base_seed, dim, func, run)` and `threefry` under every
`seed_policy` (`reference`, `unified`, `native`, `derived`), because its imported
reference campaigns were produced that way. It also samples its own
`NP = 5*D` initial population: the runner draws no shared `X0` for it, and an
`options.initial_population` passed on the lower-level path is ignored (a
documented fair-start exception). The metadata says so -
`initial_population_policy` in `environment.json` / `run_config.json` reads
`optimizer self-initializes NP = 5*D ...` and `result.notes` is
`self-init (fair-start exception)`. In a unified campaign DT-GSK therefore shares
the other optimizers' seeds (so `verify_unified_seed_schedule` still compares
it) but not their initial population; state that when you report a fair-start
comparison. See [command_reference.md](command_reference.md#37-dt-gsk) and
`src/optimizers/dt-gsk/README.md`.

## The Per-Run Comparison Needs The Statistics Toolbox

`compare_reference_runs:toolbox` means `scripts/compare_reference_runs.m` could
not find `ranksum`: the script uses the Statistics and Machine Learning Toolbox
(`ranksum`, `signrank`). Install or enable that toolbox, or fall back to the
toolbox-free aggregate checks (`gsk_validate --compare`,
`scripts/analyze_results.m`). `compare_reference_runs:missing` means neither the
given path nor `<path>\summary\per_run.csv` / `<path>\per_run.csv` exists, and
`compare_reference_runs:schema` names a required `per_run.csv` column that is
missing.

## Parallel And Serial Results Differ

Runs are sequential by default. The optional parfor path (MATLAB direct route,
`'use_parallel',true`) shares the **same deterministic seed schedule** as serial
execution, so matching `(dimension, function, run)` cells should match. If they
differ, verify that:

- `base_seed` is fixed;
- `seed_policy` is fixed (and the same on both sides);
- a previous result tree did not merge old and new rows (the runner reuses a
  `per_run.csv` row only when its stored seed, budget (`max_nfes`) and generator
  all match the active run);
- the same config (or the same flags) drove both runs.

The quickest audit point is `summary\seed_schedule.csv`: under `unified` mode the
same `(Dim,Function,Run)` key must show the same seed for every optimizer. A
clean comparison is to run a config once with `'use_parallel',true` and once
serially and diff the deterministic artifacts. Per-task floating-point reduction
order is not guaranteed identical across worker counts, so use serial execution
for a strict bit-for-bit reproducibility check.

## First Run Is Slow

The first MATLAB run of a session pays a one-time startup cost: MATLAB launches in
`-batch`, the optimizer and helper paths are added, and the MEX bridge is loaded
on first call. When parfor is enabled (`'use_parallel',true`), the parallel pool
must also start up before any timed work begins, which adds a further one-time
warmup. None of this is a failure - later cells in the same session reuse the
warm process and pool and run faster.

If the first run feels slow, it is the launch/pool warmup, not the optimizer. Keep
runs sequential (the default) when you do not need the throughput, so there is no
pool to warm. The C++ benchmark evaluation itself is native code through the MEX
bridge and does not JIT-compile at run time.

## A Build Tool Is Not On PATH

If `cmake`, `g++`, or `matlab` are not found, call them by full path instead of
bare name. Check what is on your `PATH`:

```powershell
(Get-Command cmake).Source
(Get-Command g++).Source
(Get-Command matlab).Source   # only needed for MATLAB / MEX steps
```

Two practical sources for the C++ toolchain: install WinLibs MinGW-w64 (bundles
`g++`; 4.x also bundles `cmake`), or reuse the CMake that ships inside MATLAB at
`C:\path\to\MATLAB\R2025b\bin\win64\cmake\bin\cmake.exe`. When configuring with a tool off
`PATH`, pass the compiler explicitly:

```powershell
& "C:\path\to\mingw64\bin\cmake.exe" -S . -B build -G "MinGW Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_CXX_COMPILER="C:\path\to\mingw64\bin\g++.exe"
```

For MATLAB, use any of the three location methods in
[MATLAB cannot be found](#matlab-cannot-be-found). If `ctest` reports a failed
test, the C++ build or toolchain is broken (not your experiment) - fix the
compiler/CMake and rebuild before running any optimizer.

## A Function Or Dimension Is Rejected

`gsk_run: suite S has fixed per-function dimensions; omit dimensions or use 0.`
means a nonzero dimension was given for a native-dimension suite (`cec2011`,
`cec2013lsgo`); the native value itself (for example 1000 for `cec2013lsgo`) is
rejected too. Use `--dimension 0` (or omit dimensions / set `[0]` in a config)
for those suites.

`gsk_run: dimension D is not part of suite S.` means D is not a supported
dimension of a fixed-dimension-list suite (`cec2013`, `cec2017`, `cec2020`);
`0` is not accepted there. Pick a listed dimension from
`build\gsk_list.exe --benchmarks`, or omit dimensions to run all of them.

`gsk_run: function N is not part of suite ...` means the requested function is
outside the suite's range. Check the valid ranges with:

```powershell
build\gsk_list.exe --benchmarks
```

Note that CEC2017 F2 is a valid function but is excluded from default comparisons
by the all-optimizer config (the published protocol), so it will not appear in
`all_cec2017.yml` runs.

## A Config Key Is Rejected

`Config error <file>:<line>: unknown key '...'` means a typo'd or unsupported key
is present. The loader accepts only a fixed set of keys and rejects anything else
with a line number, so a typo can never silently change an experiment. Use only
the documented keys (see [configuration.md](configuration.md) and
`configs/README.md`). One common case is `parallel: true`, which is rejected on
purpose - this version runs sequentially, so only `parallel: false` is accepted.

`data_root is not supported` means the config still has a `data_root` key. The
MATLAB runner has no data-root input (benchmark data always loads from
`<root>\benchmarks\cec_suite_cpp\<suite>\input_data`), so the key is rejected
rather than silently ignored; delete the line. Other value errors are reported
the same way, with a line number: an empty list `[]` for `functions` or
`dimensions` (use `all` for the suite defaults), and a `seed` that is negative,
fractional, or above `2^53`. A leading UTF-8 byte-order mark on the first line
is accepted.

## A Command-Line Value Is Rejected

`gsk_run: --function expects one integer, got '1,3'` (and the same message for
`--dimension`, `--runs`, and `--max-evaluations`) means a numeric flag did not
hold exactly one whole integer. Comma lists, fractions such as `--runs 2.9`, and
trailing text are rejected (exit 2) instead of being silently truncated. Repeat
the flag for several values, for example `--function 1 --function 3`.
`--max-evaluations` must be `>= 0` (`0` = suite default), `--runs` must be
`>= 1`, and `--seed` must be an integer in `[0, 2^53]`.

## A Seed Policy Or Generator Is Rejected

`run_experiment` validates `seed_policy` up front: it must be `reference`,
`unified`, `native`, or `derived`, matched case-insensitively. Anything else (a
typo such as `unifed`) raises `run_experiment:args` with
`seed_policy must be reference, unified, native, or derived` instead of silently
falling through to the hashed native/derived schedule.

`rand_generator 'auto' is resolved only under seed_policy='unified'` (likewise
`'default'`) means a native or derived run asked for a generator that only the
unified policy resolves (to `threefry` when supported, else `twister`). Use
`threefry`, `twister`, `seed`, or `state` with `native`/`derived`. Under
`reference` the generator is chosen per optimizer, so the value is ignored.

## The Seed-Schedule Verifier Warns About Missing Keys

After a multi-optimizer unified run, the root launchers call
`verify_unified_seed_schedule`, which compares the seeds of every
`(Dim,Function,Run)` key present in two or more optimizers' `seed_schedule.csv`.
A `verify_unified_seed_schedule:missingKeys` warning means one optimizer has no
row for some keys: it had failed or skipped cells (for example eGSK without the
Optimization Toolbox), or its tree was written with a different functions/runs
configuration. It is not an error and those keys are simply not compared for
that optimizer. Only `verify_unified_seed_schedule:seedMismatch` (two optimizers
with different seeds for the same key) fails the check.

---

General tip: run any tool with `--help` or no arguments to print its exact usage,
for example `build\gsk_run.exe --help`, `build\gsk_validate.exe`, or
`build\gsk_list.exe`.
