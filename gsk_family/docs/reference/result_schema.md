# Result Schema

> **What this is:** every file and column written below `results/<optimizer>/<suite>/`
> by a run, plus the post-run `verification.json` verdict. **For:** anyone
> reading, parsing, or comparing run output. **Prerequisites:** the seed contract
> in [seed_policy.md](seed_policy.md) and the suite budgets in
> [benchmark_protocol.md](benchmark_protocol.md). **After reading** you will know
> the directory layout, each CSV/JSON schema, and the numeric formatting.

Writers: `src/runners/run_experiment.m`. Readers: `gsk_validate --compare`
(`gskcec/experiment/comparison.hpp`).

## Directory layout (CEC-competition convention)

`gsk_run` writes one tree per (optimizer, suite), matching the standard CEC
results layout:

```text
results/<optimizer>/<suite>/
  summary/
    <optimizer>_<suite>_D<dim>.csv   per-dimension table (Function,Best,Median,Mean,Worst,SD)
    <optimizer>_<suite>.csv          all functions in one table (native-dim suites only: cec2011, cec2013lsgo)
    per_run.csv                      full per-run schema incl. seeds
    environment.json                 run environment + metadata
    run_config.json                  resolved run configuration (reproducibility companion)
    phase0_protocol.json             seed/protocol descriptor (reproducibility companion)
    seed_schedule.csv                Dim,Function,Run,Seed audit table
    verification.json                automatic post-run verdict (verification_1.json, etc. on rerun)
  curves/
    Figure_F<func>_D<dim>_Run#<run>.csv   median run's convergence trace
    graphs/
      Figure_F<func>_D<dim>.png           optional rendered convergence graph (write_graphs=true)
  gen_logs/
    CheckpointErrors_<optimizer>_F<func>_D<dim>.csv   per-run error at CEC checkpoints
```

Re-running an (optimizer, suite) with `overwrite=false` preserves the existing
tree. The runner resumes from `summary/per_run.csv`, skips completed run ids,
appends missing rows, and archives fixed-name refreshed artifacts under
`_archive/<timestamp>/`. With `overwrite=true`, the previous active
`results/<optimizer>/<suite>` tree is first moved under
`_overwrite_archive/<suite>_<timestamp>/` beside the suite folder, then the run
starts with a clean `summary/`, `curves/`, and `gen_logs/` tree.
Imported reference tables under `benchmarks/cec_reference_results` are never
written to. Some reference-result suite/optimizer folders also contain curated
benchmark-side `curves/`, `curves/graphs/`, and `gen_logs/` assets for future
convergence-graph generation; those files use the same schemas described below,
but they are reference evidence, not live run output. The `summary` folder name
is matched case-sensitively by the C++ tools; the runner always writes it
lowercase, so this only matters if you hand-create directories.

## summary/<optimizer>_<suite>_D<dim>.csv

```text
Function,Best,Median,Mean,Worst,SD
```

The same six-column schema as the imported reference tables, so generated and
published results are directly comparable (the C++ comparison/verification reads
these). One row per function at that dimension. `best..sd` summarize errors when
the suite has known optima, raw objectives otherwise (`statistics_basis` in
`environment.json` records which). `sd` is the sample standard deviation. For
native-dimension suites (cec2011, cec2013lsgo) a dimensionless rollup
`<optimizer>_<suite>.csv` lists every function once.

## summary/per_run.csv

```text
optimizer,suite,function,dimension,run,seed,best_fitness,error,nfes,termination,runtime_seconds
```

The complete per-run record (preserved so seeds/nfes/termination are not lost in
the aggregates). `seed` is produced by the active policy documented in
`docs/reference/seed_policy.md`; `error` is `best_fitness - optimum` with target-error
zeroing, or `NaN` for suites without published optima. Reporting exception:
ATMALS-GSK on CEC2017 reports `abs(best_fitness - optimum)` with the standard
`1e-8` zero cutoff.

Example CEC2017 row:

```text
gsk,cec2017,7,30,12,69241386,721.35,21.35,300000,max_evaluations,4.82
```

Interpretation: function 7 has optimum `700`, so
`error = 721.35 - 700 = 21.35`. The seed is the unified example seed for
`D=30`, `F7`, `run=12`, and `nfes=300000` means the full CEC2017 D30 budget was
consumed.

## summary/seed_schedule.csv

```text
Dim,Function,Run,Seed
```

The seed schedule used by the run. This file is the quickest audit point for
checking whether `unified` (default), `reference`, `native`, or `derived` seed
behavior was used. Every current run mode records deterministic seeds;
wall-clock seeding is not supported. If an output directory is reused after
changing the seed policy, old rows are left in place; the runner reuses only
per-run rows whose stored seed matches the active schedule, and the verifier
compares the latest schedule row for each `(Dim,Function,Run)` key.

Under `seed_policy='unified'`, the expected seed is exactly:

```text
seed = mod(base_seed + 1000003*Dim + 1000033*Function + 1000037*Run, 2147483646) + 1
```

The value is optimizer-independent. Root `run_all_cec*.m` launchers verify the
latest schedule rows after a multi-optimizer run, so GSK, AGSK, APGSK,
ATMALS-GSK, eGSK, FDB-AGSK, and any future optimizer must show the same seed for
the same `(Dim,Function,Run)` key.

Example unified schedule row:

```text
30,7,12,69241386
```

Every optimizer in the same multi-optimizer unified experiment should show this
same row for `D=30`, `F7`, `run=12`. A different seed means the run is not a
strict fair-start comparison.

## curves/Figure_F<func>_D<dim>_Run#<run>.csv

```text
Eval,BestError,Log10Error
```

The convergence trace of the median run (nearest the median final value) for
each (function, dimension) - the data behind a convergence figure.
`Log10Error` is blank when `BestError <= 0` (raw objectives can be non-positive).

## curves/graphs/Figure_F<func>_D<dim>.png

One rendered PNG convergence graph per summarized `(function, dimension)` cell.
PNG rendering is optional because MATLAB figure/export work can dominate the
post-processing time for short or resumed experiments. By default,
`write_graphs=false`: the runner still writes the numeric `curves/*.csv` traces
and `gen_logs/*.csv` checkpoint logs, but it skips the display-only PNG export.
Set `write_graphs=true` in `run_experiment` or a `run_all_cec*.m` launcher when
publication figures are needed immediately. If graph generation fails, the
numeric CSV artifacts remain authoritative and the run is still valid.

## gen_logs/CheckpointErrors_<optimizer>_F<func>_D<dim>.csv

```text
Run,Seed,E<c1>,E<c2>,...
```

One row per run; columns are the best-so-far error at the standard CEC
evaluation checkpoints (`[0.01 0.02 0.03 0.05 0.1 0.2 .. 1.0] x max_nfes`).

Example with `max_nfes = 300000`:

| Fraction | Evaluation checkpoint |
|---:|---:|
| 0.01 | 3000 |
| 0.10 | 30000 |
| 1.00 | 300000 |

These logs are useful for convergence plots and ablation studies because they
show how quickly an optimizer improves, not only where it finishes.

## Benchmark-side curated curves and logs

Generated experiment artifacts live under `results/<optimizer>/<suite>/`.
Curated reference artifacts may also exist under:

```text
benchmarks/cec_reference_results/<suite>/<optimizer>/curves/
benchmarks/cec_reference_results/<suite>/<optimizer>/curves/graphs/
benchmarks/cec_reference_results/<suite>/<optimizer>/gen_logs/
```

The schemas are intentionally compatible with the generated `curves/`,
`curves/graphs/`, and `gen_logs/` folders so plotting scripts can compare fresh
trajectories against preserved reference trajectories. The location determines
ownership: `results/` is append/resume run output;
`benchmarks/cec_reference_results/` is read-only benchmark evidence. Do not
delete those benchmark-side folders during cleanup, and do not let
`run_experiment` write into them.

## summary/environment.json

Fields written by `run_experiment`:

- `optimizer`, `suite`, `functions`, `dimensions_requested`, `dimensions_run`,
  `runs`, `base_seed`, `seed_policy`, `rand_generator`,
  `initial_population_policy`, `use_parallel`, `write_graphs`,
  `max_nfes_override`
- `statistics_basis` (`error_vs_optimum` | `raw_objective`), `report_zero_tol`
  (target-error zeroing tolerance), `optimizer_options` (variant metadata),
  `checkpoint_fractions`
- `data_root`, `reference_root`, `output_dir`
- `matlab_version`, `cpu_cores`, `computer`, `platform`, `git_commit`,
  `timestamp`, `runtime_seconds_total`
- `skipped_cells` (explicitly reported unavailable cells), `optimizer_notes`,
  `command` (the MATLAB call)

`initial_population_policy` records whether the optimizer drew its own first
population (`optimizer_reference_draw`) or whether unified mode supplied a
runner-generated fair-start population (`runner_supplied_X0`). In the latter
case, the matching post-initialization RNG state is restored inside the
optimizer before the first algorithmic random decision.

Compiler and build type for the C++ tooling are properties of the build tree
(`build/CMakeCache.txt`); the MEX bridge in use is recorded by its path under
`build/mex/`.

## verification.json (automatic post-run check)

Every `gsk_run` automatically compares the run against the same optimizer's
imported reference table and writes `summary/verification.json` (Mandate 1.1c).
If that file already exists, the next verdict is written to a non-colliding
name such as `verification_1.json`. Skip it only with `--no-verify`.

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

- **verdict** - `CONSISTENT` when no hard-failure check fires, else
  `DEVIATES` (and `gsk_run` exits nonzero).
- **Hard-failure checks** (catch implementation bugs, not optimization
  quality): non-finite statistics; for known-optimum suites a best error
  below `negative_error_floor` (beating the optimum is impossible if
  correct); and, at full protocol only, a mean above `gross_factor` x a
  non-trivial reference mean.
- **reduced_budget** - true when the run used an overridden budget or
  `< 25` runs; then the gross-deviation check and the win/tie/loss tally
  are informational, since a short run is legitimately worse than the
  published table.
- **win_tie_loss** - informational Wilcoxon-style tally vs the reference.

Re-run standalone with `gsk_validate --verify <run_dir> <references>
[--reduced|--full]`. The two senses of "correct" stay distinct: benchmark
*ports* are checked exactly against fixed-vector ground truth (the C++
tests); *optimizers* are checked statistically here against the same
optimizer's published table.

## Numeric formatting

Summary tables use scientific notation with at least 10 significant digits
(`%.10E`); checkpoint and curve values keep full precision (`%.16g`/`%.16e`);
seeds and counters are integers.
