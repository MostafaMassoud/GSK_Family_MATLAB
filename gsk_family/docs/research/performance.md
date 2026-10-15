# Performance Notes

> **What this is:** the baseline, measurement method, and recorded results for
> the C++ benchmark hot paths, plus a review of safe MATLAB optimizer tunings --
> all under one rule: every optimization must be numerically equivalent.
> **For:** anyone profiling or speeding up `gsk_family` who must not change a
> single result. **Prerequisites:** [Reproducibility](reproducibility.md) for
> the seed/RNG contract that tunings must preserve; a working C++ build (see
> [Runbook](../../../RUNBOOK.md)). **After reading:** you will know how
> to run `gsk_bench`, the default-vs-native build trade-off and its numerical
> equivalence proof, the indicative speedups, and which MATLAB changes are safe
> vs. stream-breaking.

Baseline, measurement method, and results for the C++ benchmark hot paths.
The governing rule: **every optimization must be numerically equivalent.**
Speed is never bought with a loosened tolerance or a changed result.

## How to measure

`gsk_bench` times raw `evaluate()` throughput on representative cells:

```powershell
build\gsk_bench.exe --root . --iterations 30000 --csv perf_default.csv
```

It evaluates deterministic in-bounds probe points (no RNG, no state change),
so numbers are comparable across builds. The CSV columns are
`suite,function,dimension,iterations,seconds,ns_per_eval,evals_per_sec`. A
tiny-iteration run is wired as the `gskcec_bench_smoke` ctest so the harness
itself cannot rot.

## Builds

- **Default Release** (`-DCMAKE_BUILD_TYPE=Release`, `-O2`): the portable,
  reference build. All ground-truth tests pass here; this is what CI ships.
- **Native** (`-DGSKCEC_NATIVE=ON`): adds `-O3 -march=native -funroll-loops
  -ffp-contract=off` (GCC/Clang) or `/O2 /arch:AVX2 /fp:precise` (MSVC).
  OFF by default for portability.

### Numerical equivalence of the native build (verified)

`-march=native` exposes FMA hardware, and the default `-ffp-contract=fast`
*fused* multiply-adds, shifting results a few ULP and breaking the exact
ground-truth matches (the 1e-12 CEC2011 WP-A and CEC2013 regression tests
caught it - 3/12 failed). Adding **`-ffp-contract=off`** restores bit-exact
IEEE results; `-O3` does not reassociate FP without `-ffast-math`, which is
never enabled. With the fix the **native build passes all 12 ctest suites (all
that existed then; the later 13th, `gskcec_cli_exit_codes`, checks CLI exit codes,
not numerics) at the same tolerances as the default build** - so the speedup below is free of
any numerical cost. This is the project's "prove no numerical change" rule in
action.

## Results (30000 evals/cell, GCC 16.1, one host; indicative, single-shot)

| Cell | Default ns/eval | Native ns/eval | Speedup |
|---|---:|---:|---:|
| cec2017 f1 D100 | 4383 | 3627 | ~17% |
| cec2017 f21 D100 (composition) | 19686 | 16678 | ~15% |
| cec2013 f1 D100 | 267 | 195 | ~27% |
| cec2013 f15 D100 | 8656 | 7436 | ~14% |
| cec2013lsgo f1 D1000 | 67014 | 55123 | ~18% |
| **cec2013lsgo f13 D905 (heaviest)** | 158290 | 106927 | **~32%** |
| cec2011 f9 D126 (EBE) | 15042 | 9608 | ~36% |
| cec2011 f17 D140 (ELD-140) | 2515 | 1871 | ~26% |
| cec2011 f21 D26 (MGA-DSM) | 14181 | 10361 | ~27% |
| cec2020 f1 D20 | 214 | 203 | ~6% |

Conclusion: the native build is a consistent ~15-36% win on the heavy
configurations with **zero numerical change**, dominated by the most expensive
cells (CEC2013LSGO at D~1000, the CEC2011 power-systems and trajectory
problems). The default build is already allocation-free on the hot path (every
port uses preallocated per-instance scratch, mirroring the reference globals),
so the remaining cost is inherent floating-point work - which the optimizer and
SIMD widening in the native build attack directly.

## What was NOT changed (and why)

- **No `-ffast-math` / `-funsafe-math-optimizations`.** They reassociate and
  flush-to-zero, changing results. Forbidden by Invariant 1.
- **No algorithmic rewrite of the ports.** They are faithful transcriptions of
  the reference numerics; rewriting risks drift for no proven gain. Any future
  rewrite must keep the ground-truth tests green at their current tolerances.
- **MATLAB optimizer vectorization** is constrained to RNG-stream-preserving
  changes (no reordering of random draws), since the optimizers reproduce the
  reference bodies bit-identically. Profile with the MATLAB profiler before
  touching them.

## MATLAB GSK-Family Performance Review (2026-06-17)

This review covers `src/common`, `src/optimizers/*`, `src/runners`, the
`run_all*` scripts, and the CEC MEX integration. The optimization rule remains
strict: preserve algorithmic logic, seed policy, RNG generator, evaluation-budget
accounting, reference quirks, and output reproducibility.
For unified fair-start experiments, the protected seed contract is
`get_cec_seed(base_seed, dim, func, run)` with
`mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1`;
do not add optimizer-specific values while tuning code.

### Implemented Safe Tunings

- `src/common/gsk_init_population.m` now uses implicit expansion:
  `lb + rand(np, dim).*(ub-lb)`. It consumes the same single `rand(np,D)` draw
  and computes the same population, but avoids materializing two `np x D` bound
  matrices.
- `src/runners/run_experiment.m` defaults to serial execution and reuses the
  already-created cell-level CEC problem handle for serial runs. Parallel mode
  still constructs one MEX handle per worker iteration, as required by the
  process-local handle registry.
- `run_experiment` now guards the cell-level MEX handle with `onCleanup`, so
  early failures cannot leave a live benchmark instance behind.
- Existing output trees are resume/add targets when `overwrite=false`.
  `run_experiment` appends `per_run.csv`, `seed_schedule.csv`, and compatible
  checkpoint logs, skips completed run ids whose seed, budget and generator
  match the active run, and archives fixed-name
  summaries/metadata/graphs before refreshing them. When `overwrite=true`, the
  previous active result tree is moved under `_overwrite_archive/` before a
  clean replacement run starts.

### Highest-Value Opportunities

- **Boundary repair allocation.** `gsk_bound_repair` still builds full `xl/xu`
  matrices with `repmat`. A column-wise midpoint repair would avoid those two
  allocations and preserve RNG behavior because no random numbers are consumed.
  Validate bitwise equality on small and large dimensions before adopting,
  because this helper is shared by all variants.
- **Runner curve conversion.** The parfor/serial bodies call
  `arrayfun(@(b) curve_value(...), gb)`. For known optima this can be replaced
  by vectorized subtraction; for unknown optima it can use `gb` directly. This is
  low risk but should be tested on known-optimum and raw-objective suites.
- **Serial CEC handle reuse beyond one cell.** The current safe reuse is per
  `(suite,function,dimension)` cell. A future runner cache could keep immutable
  problem handles across adjacent cells, but only if handle lifetime and
  memory-use profiling prove it helps long sweeps.
- **Graph generation is opt-in.** `make_convergence_graphs` can dominate the
  tail of short experiments because MATLAB figure creation and `exportgraphics`
  are slow compared with writing numeric CSV traces. Production sweeps should
  keep `write_graphs=false` and generate PNG figures later from the saved
  `curves/*.csv` and `gen_logs/*.csv` artifacts. Set `write_graphs=true` only
  when immediate presentation images are worth the extra post-processing time.
- **Logging volume.** `runs_log`, `per_run.csv`, `seed_schedule.csv`, checkpoint
  logs, and summary tables are useful audit artifacts, but verbose console
  output and per-dimension diaries cost I/O. Keep `verbose=false` for long runs;
  consider a `write_runs_log` flag after the current discrepancy investigation
  is complete.
- **CEC bridge orientation.** MATLAB optimizers are row-wise (`NP x D`) while
  the MEX bridge evaluates columns, so every evaluation transposes `pop'`. A
  row-wise MEX entry point would remove this copy, but it must be proven
  numerically identical and kept alongside the existing CEC-compatible path.
- **Population update temporaries.** Optimizers allocate junior/senior trial
  matrices and masks every generation. Some masks can be reused or scoped more
  tightly, but do not combine random draws or reorder mask creation; doing so
  changes the RNG stream.
- **Sort/reduction cost.** Adaptive variants sort fitness every generation and
  `gsk_reduction_survivors` performs a full stable sort when removing rows.
  Partial selection (`mink`/`maxk`) is tempting but may change tie behavior.
  Only replace it with tests that cover equal-fitness ties and row-order
  preservation.
- **Shared duplicated AGSK-family logic.** AGSK, APGSK, and FDB-AGSK duplicate
  the adaptive pools, reduction plan, and budget-crossing structure. A shared
  utility could reduce maintenance, but it is a readability refactor rather
  than an immediate speed win and should wait until reproduction discrepancies
  are closed.
- **Parallel scheduling.** Run-level `parfor` is correct when workers can see
  the source tree and MEX bridge. For production, prefer coarse parallelism over
  independent `(optimizer, suite, dimension)` jobs from the shell or scheduler;
  it avoids parfor startup cost and isolates failures. If MATLAB parallelism is
  re-enabled, attach required source files explicitly and smoke-test one
  CEC2017 cell before full runs.

### Changes to Avoid Unless Deliberately Breaking Stream Compatibility

- Vectorizing ATMALS-GSK local search or AGSK/APGSK adaptive branches can easily
  change the order and number of `rand` calls. Do not rewrite those loops unless
  the replacement emulates the original draw order exactly.
- Removing apparently unused random draws is not safe. Examples include
  ATMALS-GSK's `randperm` in the local-search block and APGSK's unused
  initialization `K` vector; both preserve downstream RNG alignment.
- Replacing stable sorts with faster unstable selections can change tie removal
  order and therefore later trajectories.
- Changing eGSK's `fmincon` options, IP trigger, or local-refinement budget is a
  behavioral change, not a performance tuning.
- DT-GSK follows its reference implementation's draw order per Threefry
  substream and its floating-point operation order (sequential and pairwise
  sums as the reference computes them, stable sorts); vectorizing a sum or
  swapping a sort changes trajectories. A speed rewrite must keep runs bit-identical to the current version, as the
  compact three-file version did against the line-by-line port (see
  `src/optimizers/dt-gsk/README.md`).

### Profiling Checklist

Use the MATLAB profiler on a representative reduced cell before any optimizer
rewrite:

```matlab
root = '<repo>/gsk_family';
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'build','mex'));
profile clear; profile on;
run_experiment('optimizer','gsk','suite','cec2017','functions',[1], ...
    'dimensions',[10],'runs',3,'base_seed',20240620,'max_nfes',1000, ...
    'project_root',root,'output_dir',fullfile(root,'results','_profile','gsk'), ...
    'overwrite',true,'verbose',false,'seed_policy','unified', ...
    'rand_generator','threefry','use_parallel',false);
profile off; profile viewer;
```

Profile at least one baseline GSK cell, one adaptive AGSK/APGSK/FDB-AGSK cell,
and one eGSK cell with the Optimization Toolbox state recorded. Keep the
generated `seed_schedule.csv`, `per_run.csv`, and summary CSVs from before and
after each tuning and compare them before accepting any speed change.

## Reproducing

```powershell
# default
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
build\gsk_bench.exe --root . --csv perf_default.csv

# native (must still pass ctest 13/13 - that is the equivalence proof)
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DGSKCEC_NATIVE=ON
cmake --build build -j
ctest --test-dir build --output-on-failure
build\gsk_bench.exe --root . --csv perf_native.csv
```
