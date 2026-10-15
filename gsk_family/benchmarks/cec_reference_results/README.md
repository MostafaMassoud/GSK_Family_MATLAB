# benchmarks/cec_reference_results

**This folder vs the other two:** `cec_reference_results` holds **imported,
read-only reference evidence** - published aggregate result tables plus curated
reference-side `curves/`, `curves/graphs/`, and `gen_logs/` convergence assets.
The aggregate tables are the numbers from prior papers that
`gsk_run`/`gsk_validate` compare fresh runs against; the convergence assets are
preserved for future graph generation and trajectory audits. This folder
contains data only, never code, and is never written to by a normal run.
`cec_suite_cpp` holds *the benchmark problems themselves* plus the nested
`cec_tools` C++ helper library, CLIs, MEX bridge, and tests.

The aggregate CSV/TXT files are the comparison baseline for the automatic
post-run verdict (`verification.json`) and for the paper's comparison tables.
Treat every file in this folder as read-only curated reference material: never
edit, overwrite, or merge it during a run, and never write generated results
here (those go under `results/`).

## Directory structure

```text
benchmarks/cec_reference_results/
  cec2011/{gsk,agsk,apgsk,fdb-agsk,egsk,atmals-gsk}/
    *_cec2011*.csv                                    aggregate/native-dimension tables
    curves/                                           curated median-run convergence traces
      graphs/                                         curated rendered convergence PNGs
    gen_logs/                                         curated checkpoint-error logs
  cec2017/{gsk,agsk,apgsk,fdb-agsk,egsk,atmals-gsk}/
    *_cec2017_D{10,30,50,100}.csv                     aggregate tables; F2 excluded
    curves/                                           curated median-run convergence traces
      graphs/                                         curated rendered convergence PNGs
    gen_logs/                                         curated checkpoint-error logs
  cec2013/gsk/                                        gsk_cec2013_D{10,30,50}.csv
  cec2013lsgo/{decc-g,mos}/                           *_cec2013lsgo.csv
  cec2020/agsk/                                       agsk_cec2020_D{05,10,15,20}.csv
```

The folder name under each suite is the reference algorithm name; optimizer
ids use the same hyphenated slugs (`atmals-gsk`, `fdb-agsk`).

## Column schema

Most files use `Function,Best,Median,Mean,Worst,SD`. The C++ loader
(`gskcec::load_reference_file`) normalizes `1`/`F1`/`f1` to a single function
id and accepts missing statistics written as empty cells, `-`, `nan`, or `N/A`
(used by the AGSK CEC2020 D=5 table). No Python is involved anywhere.

## Curated convergence assets

Some CEC2011 and CEC2017 optimizer folders also contain:

```text
curves/Figure_F<func>_D<dim>_Run#<run>.csv
curves/graphs/Figure_F<func>_D<dim>.png
gen_logs/CheckpointErrors_<optimizer>_F<func>_D<dim>.csv
```

These files mirror the generated-result schemas documented in
`docs/reference/result_schema.md`, but their location gives them a different meaning:
they are benchmark-side curated artifacts that can be used later to generate
publication convergence graphs, reuse already rendered graph images, or compare
trajectory shapes against fresh runs. They are not temporary output and they
are not cleanup candidates.

When new convergence files are promoted here, record where they came from
(commit, seed policy, MATLAB version, suite, dimension, function set, and run
count) before replacing or adding them. Normal `run_all*` and `run_experiment`
execution must continue writing new curves and logs under `results/`.

## Distinctness

`cec2013` (standard suite) and `cec2013lsgo` (large-scale suite) are separate
and must never be merged.

## How comparisons use these files

The comparison pipeline reads the `Mean` column for the matching
`(optimizer, suite, dimension, function)` key. It never writes back to this
folder. In MATLAB `run_experiment`, the console table reports
`Delta(New-Old) = generated_mean - reference_mean`; absolute deltas below
`1e-8` are displayed as zero and counted as equal so floating-point noise is not
reported as a meaningful change.

When a reference table is absent, the run is still valid but the comparison is
reported as missing reference data. Examples include APGSK/eGSK/FDB-AGSK on some
non-native suites and CEC2013/CEC2013LSGO optimizer combinations without
published tables.

## Citation and provenance practice

When using these tables in a paper or thesis:

1. cite the original paper/reference release that produced the table;
2. state the project commit or archive used for the port;
3. state whether the experiment used reference mode or unified mode;
4. preserve the generated `environment.json`, `seed_schedule.csv`, and
   `per_run.csv` next to any aggregate table.

Never merge generated results into this folder as an automatic side effect of a
run. New generated baselines belong under `results/` or a clearly named
external archive until they are deliberately curated as reference evidence.
