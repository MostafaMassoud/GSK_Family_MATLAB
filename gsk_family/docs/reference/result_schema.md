# Result Schema

> **What this is:** every file and column written below `results/<optimizer>/<suite>/`
> by a run, plus the post-run `verification.json` verdict. **For:** anyone
> reading, parsing, or comparing run output. **Prerequisites:** the seed contract
> in [seed_policy.md](seed_policy.md) and the suite budgets in
> [benchmark_protocol.md](benchmark_protocol.md). **After reading** you will know
> the directory layout, each CSV/JSON schema, and the numeric formatting.

Writers: `src/runners/run_experiment.m`. Readers: `gsk_validate --compare`
(`gskcec/experiment/comparison.hpp`), which skips `_overwrite_archive/` and
`_archive/` folders below the root it is given.

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
tree. The runner resumes from `summary/per_run.csv`: a completed run id is
skipped only when its stored `seed`, cell budget (`max_nfes`), and effective
`rand_generator` all match the active run. Any other row is stale: that run id
is re-run and its new row appended, while the stale row stays in the file as
history. Missing rows are appended, and fixed-name refreshed artifacts are
archived under `_archive/<timestamp>/`. With `overwrite=true`, the previous active
`results/<optimizer>/<suite>` tree is first moved under
`_overwrite_archive/<suite>_<timestamp>/` beside the suite folder, then the run
starts with a clean `summary/`, `curves/`, and `gen_logs/` tree.
Imported reference tables under `benchmarks/cec_reference_results` are never
written to: `run_experiment` refuses any `output_dir` inside (or equal to) that
tree on every run, before anything is created (`run_experiment:outputUnsafe`).
Some reference-result suite/optimizer folders also contain curated
benchmark-side `curves/`, `curves/graphs/`, and `gen_logs/` assets for future
convergence-graph generation; those files use the same schemas described below,
but they are reference evidence, not live run output. The `summary` folder name
is matched case-sensitively by the C++ tools; the runner always writes it
lowercase, so this only matters if you hand-create directories.

## `summary/<optimizer>_<suite>_D<dim>.csv`

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
optimizer,suite,function,dimension,run,seed,best_fitness,error,nfes,termination,runtime_seconds,max_nfes,rand_generator
```

The complete per-run record (preserved so seeds/nfes/termination are not lost in
the aggregates). `seed` is produced by the active policy documented in
`docs/reference/seed_policy.md`; `error` is `best_fitness - optimum` with target-error
zeroing. On `cec2011` (no published optima, `optimum = NaN`) the `error` column
is `NaN`. On `cec2013lsgo` the port's `optimum()` is `0`, so the column holds
`best_fitness - 0`, i.e. the raw objective, with no zero cutoff; its statistics
basis is still `raw_objective`. Reporting exception: ATMALS-GSK on CEC2017
reports `abs(best_fitness - optimum)` with the standard `1e-8` zero cutoff.
`max_nfes` is the cell's effective evaluation budget (after any `max_nfes`
override) and `rand_generator` is the effective generator the run used; together
with `seed` they decide whether a row is reused on resume (see above).
`best_fitness` and `error` are written with `%.17g` (round-trip precision), so a
summary recomputed after a resume equals the one an uninterrupted run would
have written.

Example CEC2017 row (values shortened for readability):

```text
gsk,cec2017,7,30,12,69241386,721.35,21.35,300000,max_evaluations,4.82,300000,threefry
```

Interpretation: function 7 has optimum `700`, so
`error = 721.35 - 700 = 21.35`. The seed is the unified example seed for
`D=30`, `F7`, `run=12`, `nfes=300000` means the full CEC2017 D30 budget was
consumed, the trailing `300000` is that cell's budget, and `threefry` is the
generator.

**Older files.** A `per_run.csv` written before the `max_nfes,rand_generator`
columns existed (11 columns) is upgraded on the first resume: the file is first
archived to `summary/_archive/<timestamp>/`, then its header is replaced and each
older row gets the budget and generator recorded in the tree's previous
`run_config.json` (a suite-default budget is resolved per cell). When that
configuration is unavailable the two fields are left blank, which never matches,
so those run ids are re-run. The upgrade can only assign the last session's
budget and generator; a legacy tree that already mixed budgets or generators
should be rerun with `overwrite=true`.

The imported DT-GSK reference evidence
(`benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv`) also
has the 11-column layout. It is read-only and never upgraded;
`scripts/compare_reference_runs.m` reads columns by name, so it accepts both
layouts.

## summary/seed_schedule.csv

```text
Dim,Function,Run,Seed
```

The seed schedule used by the run. This file is the quickest audit point for
checking whether `unified` (default), `reference`, `native`, or `derived` seed
behavior was used. Every current run mode records deterministic seeds;
wall-clock seeding is not supported. If an output directory is reused after
changing the seed policy, budget, or generator, old rows are left in place; the
runner reuses only per-run rows whose stored seed, budget (`max_nfes`), and
generator match the active run, and the verifier compares the latest schedule
row for each `(Dim,Function,Run)` key. When a reused run's latest
`seed_schedule.csv` row came from another configuration, the runner appends the
active seed again, so the latest row per key always describes the active
schedule; an identical rerun appends nothing.

Under `seed_policy='unified'`, the expected seed is exactly:

```text
seed = mod(base_seed + 1000003*Dim + 1000033*Function + 1000037*Run, 2147483646) + 1
```

The value is optimizer-independent. Root `run_all_cec*.m` launchers verify the
latest schedule rows after a multi-optimizer run
(`verify_unified_seed_schedule`), so GSK, AGSK, APGSK, ATMALS-GSK, eGSK,
FDB-AGSK, DT-GSK, and any future optimizer must show the same seed for the same
`(Dim,Function,Run)` key. Seeds are compared on every key present in two or more
optimizers' schedules. A key missing from an optimizer (a failed or skipped
cell, or a tree written with a different functions/runs configuration) produces
a `verify_unified_seed_schedule:missingKeys` warning; only a seed mismatch
(`verify_unified_seed_schedule:seedMismatch`) fails.

Example unified schedule row:

```text
30,7,12,69241386
```

Every optimizer in the same multi-optimizer unified experiment should show this
same row for `D=30`, `F7`, `run=12`. A different seed means the run is not a
strict fair-start comparison. DT-GSK is unified-only, so its schedule holds
these unified seeds under every `seed_policy` (and its `per_run.csv`
`rand_generator` is always `threefry`).

## `curves/Figure_F<func>_D<dim>_Run#<run>.csv`

```text
Eval,BestError,Log10Error
```

The convergence trace of the median run (nearest the median final value) for
each (function, dimension) - the data behind a convergence figure.
`Log10Error` is blank when `BestError <= 0` (raw objectives can be non-positive).

After a resume the median is re-selected over the old and new runs, and only
that run's curve is kept. Curves written by earlier sessions for other run ids,
and a same-id curve left by a stale row (its final value no longer matches the
run's statistic), are moved to `curves/_archive/<timestamp>/`; the cell's graph
PNG is moved to `curves/graphs/_archive/<timestamp>/` the same way (and redrawn
from the median trace when `write_graphs=true`). If the median is an earlier run
whose trace was never stored, the cell has no curve and the resume notes say so.

## `curves/graphs/Figure_F<func>_D<dim>.png`

One rendered PNG convergence graph per summarized `(function, dimension)` cell.
PNG rendering is optional because MATLAB figure/export work can dominate the
post-processing time for short or resumed experiments. By default,
`write_graphs=false`: the runner still writes the numeric `curves/*.csv` traces
and `gen_logs/*.csv` checkpoint logs, but it skips the display-only PNG export.
Set `write_graphs=true` in `run_experiment` or a `run_all_cec*.m` launcher when
publication figures are needed immediately. If graph generation fails, the
numeric CSV artifacts remain authoritative and the run is still valid.

## `gen_logs/CheckpointErrors_<optimizer>_F<func>_D<dim>.csv`

```text
Run,Seed,E<c1>,E<c2>,...
```

One row per run; columns are the best-so-far error at the standard CEC
evaluation checkpoints (`[0.01 0.02 0.03 0.05 0.1 0.2 .. 1.0] x max_nfes`).
Convergence counters that cross the budget (eGSK's `max_nfes + 1` counter and IP
overshoot; ATMALS-GSK and FDB-AGSK already clip their recorded counters) are
clipped to `max_nfes` for the checkpoint lookup, so `E<max_nfes>` equals the
per-run final error. Curated `gen_logs`
under `benchmarks/cec_reference_results` predate this and may show the
penultimate generation in their last column.

Example with `max_nfes = 300000`:

| Fraction | Evaluation checkpoint |
|---:|---:|
| 0.01 | 3000 |
| 0.10 | 30000 |
| 1.00 | 300000 |

These logs are useful for convergence plots and ablation studies because they
show how quickly an optimizer improves, not only where it finishes.

## `gen_logs/BestTrace_<optimizer>_F<func>_D<dim>.csv` (optional)

Written only when the run uses `'trace_points',n` (a launcher's
`trace_points` CONFIG entry). Same layout as the checkpoint file
(`Run,Seed,E<b1>,E<b2>,...`), at `n` log-spaced budgets from 1 to `max_nfes`
(`unique(round(logspace(0, log10(max_nfes), n)))`, so possibly fewer than `n`
columns), taken from the same convergence records with the same clipping rule.
`scripts/plot_performance.m` prefers it to the checkpoint file for ERT and
ECDF. `environment.json` records `trace_points` (0 = off).

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

- `optimizer` (the name the run was given: an optimizer, or an
  `algorithms.ini` alias), `base_optimizer` (the code it ran; equal to
  `optimizer` except for an alias), `alias_settings` (the alias's settings as
  one line, e.g. `kf = 0.7, kr = 0.8`; `''` when none), `aliases_file` (the
  file it came from; `''` when not an alias)
- `suite`, `functions`, `dimensions_requested`, `dimensions_run`,
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

`seed_policy` is written as `<seed_policy>: <scheme>`, for example
`unified: seed = mod(uint64(base_seed) + ...) + 1; ...`; the same scheme text
appears as `seed_scheme` in `run_config.json`. Under `reference` the scheme
describes only the active optimizer's formula and generator, for example
`reference: seed = dim*func*run (base_seed unused); agsk reference generator:
legacy seed (mcg16807)`.

`initial_population_policy` records whether the optimizer drew its own first
population or whether unified mode supplied a runner-generated fair-start
population. The three values written by `run_experiment` are:

- `optimizer draws its own reference/native initial population`
  (`reference`, `native`, `derived`)
- `runner-generated shared X0 from get_cec_seed(base_seed,dim,func,run);
  post-initialization rng state restored inside optimizer` (`unified`)
- `optimizer self-initializes NP = 5*D from its own init substream; runner X0
  not used (documented DT-GSK fair-start exception)` (`dt-gsk`, every policy)

In the unified case, the matching post-initialization RNG state is restored
inside the optimizer before the first algorithmic random decision. For
`dt-gsk`, the `seed_policy` scheme text states that the unified schedule and
`threefry` are forced under every `seed_policy`, and `optimizer_notes` holds
`self-init (fair-start exception)`.

Compiler and build type for the C++ tooling are properties of the build tree
(`build/CMakeCache.txt`); the MEX bridge in use is recorded by its path under
`build/mex/`.

## summary/run_config.json and summary/phase0_protocol.json

Reproducibility companions written by `run_experiment` next to
`environment.json`. Besides the run settings (`base_seed`, `seed_policy`,
`seed_scheme`, `rand_generator`, `runs`, dimensions, functions,
`max_nfes_override`, `optimizer_options`, ...), both record the seed formula
actually used: `run_config.json` as `seed_formula` and `phase0_protocol.json`
as `seed_policy.formula`, filled for every policy (for example
`get_cec_seed(base_seed, dim, func, run)` under `unified`). The audit strides
`stride_run` / `dim_stride` / `func_stride` mirror that formula. Under
`reference`, `gsk` / `egsk` / `atmals-gsk` record `1` / `0` / `9973`
(`base_seed + 9973*func + (run-1)`), while `agsk` / `apgsk` / `fdb-agsk` record
the three strides as `null` and leave `phase0_protocol.json`'s
`seed_policy.base_seed_field` and `seed_policy.stride_field` empty, since their
seed is `dim*func*run` and `base_seed` is unused. `dt-gsk` records the unified
formula and strides under every policy, and its `run_config.json` adds
`profile: "pub"`. `run_config.json` also records `alg_name` (the run's name),
`base_optimizer` and `alias_settings` (as in `environment.json`); `gsk` runs
record the `KF`/`KR`/`K`/`P` values they used, an alias's own values included.
A resumed tree whose recorded `alias_settings` differ from the alias's current
settings is refused, so one tree never mixes two configurations.

An alias's files are named after the alias: its tree (from the launchers)
is `results/_run_all/<alias>/<suite>/`, with `<alias>_<suite>_D<dim>.csv`,
`CheckpointErrors_<alias>_F<f>_D<d>.csv`, and `<alias>` in the `optimizer`
column of `per_run.csv`.

## results/analysis/compare/<suite>/settings_<suite>.csv and .tex

Written by `scripts/compare_algorithms.m` (and `run_compare_algorithms.m`)
from each compared tree's `environment.json`. Columns: `name`, `label`,
`base` (the code it ran), `np_init` and `min_pop_size` (the values used, with
"(original)" when the optimizer's published value applies; "fixed" for GSK,
eGSK and ATMALS-GSK, which keep their population size), and `other_settings`
(an alias's other settings, or `original`). The `.tex` file is the same table
for a manuscript.

## results/analysis/compare/<suite>/ statistics files

Written by `scripts/compare_algorithms.m`. `<dimension>` is the dimension,
`native` (CEC2011, CEC2013-LSGO) or `overall`.

- `ranksum_<suite>.csv`: `dimension, function, proposed, competitor, p_value,
  p_holm, sign, sign_holm, a12, cliffs_delta, effect`. `p_holm` is Holm-adjusted
  over the functions of the dimension, per competitor; `sign`/`sign_holm` are
  `+`, `=` or `-` from the proposed optimizer's side; `a12` is
  P(proposed < competitor) + 0.5 P(equal); `cliffs_delta = 2*a12 - 1`;
  `effect` is negligible (|delta| < 0.147), small (< 0.33), medium (< 0.474)
  or large.
- `friedman_<suite>.csv`: `dimension, optimizer, mean_rank, position,
  n_functions, chi2, df, p_value, iman_davenport_f, id_df1, id_df2, id_p_value`.
- `posthoc_<suite>.csv`: `dimension, control, competitor, mean_rank_control,
  mean_rank_competitor, z, p_unadjusted, p_bonferroni_dunn, p_holm,
  p_hochberg, p_finner, significant_holm` (z = rank difference /
  sqrt(k(k+1)/(6N))).
- `nemenyi_<suite>.csv`: `dimension, k, n_functions, alpha, q_alpha,
  critical_difference` (CD = q_alpha sqrt(k(k+1)/(6N))).

## results/analysis/statistics/<suite>/ and complexity/<suite>/

`scripts/plot_statistics.m` writes `cd_<suite>_<dimension>`,
`box_<suite>_F<f>_D<d>`, `box_<suite>_<dimension>_overview`, optional
`violin_...`, `ranks_<suite>_bars`, `ranks_<suite>_radar` and
`runtime_<suite>` as PNG/PDF. `compare_algorithms` writes
`runtime_<suite>.csv` (`dimension, function, optimizer, runs, mean_seconds,
sd_seconds, median_seconds`) and `runtime_<suite>.tex`.

`scripts/plot_performance.m` writes `results/analysis/performance/<suite>/`:
`performance_<suite>.csv` (`dimension, function, optimizer, target, runs,
successes, success_rate, ert`; `ert` is `Inf` when no run reaches the
target), `ert_<suite>_<dimension>.tex` and the ECDF figures
`ecdf_<suite>_<dimension>` and `ecdf_<suite>_overall`.

`scripts/plot_sensitivity.m` writes
`results/analysis/sensitivity/<suite>/<base>/sensitivity_<suite>_<base>.csv`
(`group, <param>[, <param2>], alias, mean_rank`) and its figures;
`scripts/plot_ablation.m` writes
`results/analysis/ablation/<suite>/<base>/ablation_<suite>_<base>.csv`
(`version, label, switched_off, mean_rank, full_wins, ties, full_losses,
signed_rank_p_<group>...`), the `.tex` table and the chart. Both keep the full
`compare_algorithms` tables of their runs in a `compare/` subfolder.

`scripts/cec_complexity.m` writes `complexity_<suite>.csv` (`optimizer, label,
dimension, function, evals, T0, T1, T2_hat, T2_runs, ratio`, seconds) and
`complexity_<suite>.tex`.

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
  published table. A standalone `gsk_validate --verify` derives it from the
  run's `summary/environment.json` (`runs`, `max_nfes_override`, the same rule
  `gsk_run` applies; full protocol when the file is absent) unless `--reduced`
  or `--full` is passed.
- **win_tie_loss** - informational Wilcoxon-style tally vs the reference.
- **optimizer** / **suite** - comma-joined when one run directory mixes
  several; each row is still judged under its own suite's rules and against
  its own reference row.
- **failures** - per-function reasons; numbers are printed in `%.10g` style
  (for example `reference 1e-07`, `below floor -1e-06`), not with six fixed
  decimals.

Re-run standalone with `gsk_validate --verify <run_dir> <references>
[--reduced|--full]` (the flags only override the protocol read from
`environment.json`). The two senses of "correct" stay distinct: benchmark
*ports* are checked exactly against fixed-vector ground truth (the C++
tests); *optimizers* are checked statistically here against the same
optimizer's published table.

## Numeric formatting

Summary tables use scientific notation with at least 10 significant digits
(`%.10E`); checkpoint and curve values keep full precision (`%.16g`/`%.16e`);
`per_run.csv` writes `best_fitness` and `error` with `%.17g` (round-trip) and
`runtime_seconds` with `%.6f`; seeds and counters are integers. Older
`per_run.csv` rows written with `%.10e` still parse.
