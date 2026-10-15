# Troubleshooting

> **What this is:** fixes for the problems newcomers hit most with the
> `gsk_family` MATLAB + C++ project: the MEX bridge, benchmark data, output
> paths, reference mismatches, the eGSK toolbox requirement, and
> parallel-vs-serial determinism.
> **For:** anyone whose run did not behave as [tutorial.md](tutorial.md),
> [user_guide.md](user_guide.md), or [runbook.md](runbook.md) describes.
> **Prerequisites:** none. Terms used here are defined in
> [glossary.md](../reference/glossary.md).
> **After reading:** you will be able to diagnose and resolve the common
> failures, and know which reference page to consult for the rest.

Find your symptom in the table, then jump to the section.

| Symptom | Section |
|---|---|
| `gskcec:mexMissing` / runner stops at startup | [The MEX bridge cannot be found](#the-mex-bridge-cannot-be-found) |
| `gsk_run`: MATLAB invocation failed | [MATLAB cannot be found](#matlab-cannot-be-found) |
| Benchmark data fails to load | [Benchmark data cannot be loaded](#benchmark-data-cannot-be-loaded) |
| Output path rejected | [The output root is rejected](#the-output-root-is-rejected) |
| Verdict `DEVIATES` / nonzero exit | [Reference comparison reports DEVIATES](#reference-comparison-reports-deviates) |
| `CONSISTENT` but win/tie/loss all 0 | [CONSISTENT with no comparison](#consistent-with-no-comparison) |
| eGSK `egsk:fminconUnavailable` | [eGSK requires the Optimization Toolbox](#egsk-requires-the-optimization-toolbox) |
| Parallel and serial disagree | [Parallel and serial results differ](#parallel-and-serial-results-differ) |
| First run slow / pool warmup | [First run is slow](#first-run-is-slow) |
| `cmake` / `g++` / `matlab` not found | [A build tool is not on PATH](#a-build-tool-is-not-on-path) |
| `gsk_run: dimension ...` / `function ...` rejected | [A function or dimension is rejected](#a-function-or-dimension-is-rejected) |
| `Config error <file>:<line>: unknown key` | [A config key is rejected](#a-config-key-is-rejected) |

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

The runner could not find the benchmark input-data files. Check that `data_root`
points at:

```text
benchmarks\cec_suite_cpp
```

When using a config, prefer rooting paths to the current project so a stale
absolute path from another machine cannot leak in:

```powershell
build\gsk_run.exe --config configs\smoke.yml --root .
```

`--root .` rewrites relative `data_root`, `reference_root`, and `output_root`
under the current project. You can confirm a suite's data loads and evaluates to
finite numbers, with no optimizer and no MATLAB, using the smoke check:

```powershell
build\gsk_validate.exe --suite cec2017 --smoke
```

(CEC2020 prints explicit `SKIP ...` lines for the few cells without shuffle data
- functions 1 and 8 at D=5 and D=15 - which is expected, not a failure.)

## The Output Root Is Rejected

This is a safety guard, not a bug. The runner refuses to write generated results
inside the imported reference tree:

```text
benchmarks\cec_reference_results
```

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
"too few evaluations", not "wrong" - re-check with `--reduced`:

```powershell
build\gsk_validate.exe --verify results\gsk\cec2017 benchmarks\cec_reference_results --reduced
```

Open `summary\verification.json` -> `failures` for the exact (function,
dimension) and reason. A non-finite or negative-error failure indicates a real
bug; confirm you are also comparing like with like (same suite, function ids,
dimensions, optimizer id, and statistics basis on both sides). The verdict
fields, thresholds, and comparison rules are in
[result_schema.md](../reference/result_schema.md) and
[benchmark_protocol.md](../reference/benchmark_protocol.md).

## CONSISTENT With No Comparison

A verdict of `CONSISTENT` with `win/tie/loss` all `0` and `missing_reference > 0`
is not an error - it means there is no published reference table for that
optimizer/suite, so there is nothing to contradict. Reference tables exist only
for what was actually published: CEC2017 has all six optimizers, CEC2011 has only
`gsk` and `atmals-gsk`, and CEC2020 has only `agsk`. Everything else (for example
`apgsk`/`egsk`/`fdb-agsk` on CEC2011, or anything on CEC2013/LSGO) is a
framework-level extension and reports `missing_reference`. The run is still valid;
there is simply nothing to compare against.

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

## Parallel And Serial Results Differ

Runs are sequential by default. The optional parfor path (MATLAB direct route,
`'use_parallel',true`) shares the **same deterministic seed schedule** as serial
execution, so matching `(dimension, function, run)` cells should match. If they
differ, verify that:

- `base_seed` is fixed;
- `seed_policy` is fixed (and the same on both sides);
- a previous result tree did not merge old and new rows (the runner reuses a
  `per_run.csv` row only when its stored seed still matches the active policy);
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

`gsk_run: dimension D is not part of suite ...` means a nonzero dimension was
given for a native-dimension suite (`cec2011`, `cec2013lsgo`). Use `--dimension
0` (or omit dimensions / set `[0]` in a config) for those suites.

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

---

General tip: run any tool with `--help` or no arguments to print its exact usage,
for example `build\gsk_run.exe --help`, `build\gsk_validate.exe`, or
`build\gsk_list.exe`.
