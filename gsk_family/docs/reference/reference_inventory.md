# Provenance Inventory

> **What this is:** The provenance record for the self-contained `gsk_family`
> project -- where each maintained artifact lives (MATLAB optimizers, C++
> benchmark ports, input data, imported reference tables, expected-value test
> data) and what it is for. **For:** maintainers tracing the origin or authority
> of any committed artifact. **Prerequisites:** none; per-suite porting detail is
> in [porting_notes.md](porting_notes.md). **After reading:** you know which
> committed files are the validation oracle and which are read-only imported
> reference evidence.

This page records the provenance that matters for the current, self-contained
project. The external source archive used during the original port is no longer
part of this workspace, so the maintained artifacts are the committed MATLAB
optimizers, C++ benchmark ports, imported input data, imported reference-result
tables, and committed expected-value test data.

## Current Artifacts

| Area | Current location | Maintained purpose |
|---|---|---|
| MATLAB optimizers | `src/optimizers/` | GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK, and DT-GSK algorithm implementations. |
| Shared MATLAB helpers | `src/common/` | Initialization, boundary handling, gained-shared operators, FDB scoring, seed/RNG helpers, and statistics utilities. |
| Experiment runners | `src/runners/`, `src/experiments/` | Reproducible experiment execution, benchmark construction, result writing, and default matrices. |
| CEC benchmark ports | `benchmarks/cec_suite_cpp/<suite>/src/` | Standalone C++20 implementations of CEC2011, CEC2013, CEC2013LSGO, CEC2017, and CEC2020. |
| CEC input data | `benchmarks/cec_suite_cpp/<suite>/input_data/` | Shift, rotation, shuffle, and suite-specific data consumed by the C++ ports. |
| CEC support tools | `benchmarks/cec_suite_cpp/cec_tools/` | C++ library headers, CLIs, MEX bridge source, comparison code, and unit tests. |
| Published reference evidence | `benchmarks/cec_reference_results/` | Imported read-only result tables plus curated convergence assets used for verification, comparison reports, and future convergence plots. |
| Expected-value test data | `benchmarks/cec_suite_cpp/cec_tools/tests/data/` | Committed regression oracle for C++ tests and the optional MATLAB MEX smoke test. |

## Algorithm Provenance

| Optimizer | Current entry point | Notes |
|---|---|---|
| GSK | `src/optimizers/gsk/gsk_optimize.m` | Baseline GSK implementation with shared junior/senior operators in `src/common/`. |
| AGSK | `src/optimizers/agsk/agsk_optimize.m` | Adaptive parameter pools and population reduction. |
| APGSK | `src/optimizers/apgsk/apgsk_optimize.m` | APGSK variant using the shared adaptive GSK machinery. |
| ATMALS-GSK | `src/optimizers/atmals-gsk/atmals_gsk_optimize.m` | Multi-parameter adaptation, roulette selection, and local-search logic. |
| eGSK | `src/optimizers/egsk/egsk_optimize.m` | eGSK variant with late-stage refinement helpers. |
| FDB-AGSK | `src/optimizers/fdb-agsk/fdb_agsk_optimize.m` | FDB case selection plus best/ranking/roulette scoring helpers. |
| DT-GSK | `src/optimizers/dt-gsk/dt_gsk_optimize.m` | Dimension-Tiered GSK, ported from the DT-GSK reference implementation (Python, MIT license) v2.46, <https://github.com/MostafaMassoud/DT-GSK>; `pub` profile in `dt_gsk_config.m`, SGSM interaction graph in `dt_gsk_graph.m`. Port record and validation: `src/optimizers/dt-gsk/README.md`. |

## Benchmark Provenance

| Suite | Current port | Validation record |
|---|---|---|
| CEC2011 | `benchmarks/cec_suite_cpp/cec2011/src/` | 22 real-world problems, committed CEC2011 bounds/probes/expected values, MATLAB smoke coverage via the MEX bridge. |
| CEC2013 | `benchmarks/cec_suite_cpp/cec2013/src/cec2013_problem.cpp` | 28-function standard suite, optimum checks, and `cec2013_regression.csv` saved-vector validation. |
| CEC2013LSGO | `benchmarks/cec_suite_cpp/cec2013lsgo/src/` | 15-function large-scale suite with explicit data-root loading and smoke validation. |
| CEC2017 | `benchmarks/cec_suite_cpp/cec2017/src/cec2017_problem.cpp` | 30-function suite, fixed-vector expected values and known preserved quirks documented in `docs/reference/porting_notes.md`. |
| CEC2020 | `benchmarks/cec_suite_cpp/cec2020/src/cec2020_problem.cpp` | 10-function suite, AGSK-compatible optimum vector, fixed-vector expected values and missing-data behavior documented. |

## Reference Result Tables and Convergence Assets

Imported published result tables and curated convergence assets are committed
under:

```text
gsk_family/benchmarks/cec_reference_results/
```

Current reference inventory:

- Aggregate summary tables remain the only inputs used by
  `gsk_validate --references` and post-run comparison reports.
- Curated `curves/` files preserve median-run convergence traces for future
  graph generation.
- Curated `curves/graphs/` files preserve rendered PNG convergence graphs.
- Curated `gen_logs/` files preserve per-run checkpoint errors for trajectory
  comparisons and ablation plots.
- The current CEC2011/CEC2017 curated convergence archive contains 828 curve
  CSV files, 828 rendered graph PNG files, and 828 checkpoint-log CSV files.
- CEC2013LSGO reference folders: `cec2013lsgo/decc-g/`, `cec2013lsgo/mos/`,
  and `cec2013lsgo/dt-gsk/`.
- CEC2017 F2 is intentionally absent from aggregate reference tables.
- `gsk_list --references` loads 165 files / 1411 rows. Only CSV/TXT files
  directly under `<suite>/<optimizer>/` are reference tables; nested folders
  (`curves/`, `gen_logs/`, `evidence/`) are ignored by the loader.

DT-GSK reference results (`<suite>/dt-gsk/`, 30 tables / 297 rows) were
imported from the DT-GSK reference implementation (Python, MIT license, tag
`v2.46`). They were produced by that implementation, not by this toolkit, so
agreement with them is cross-implementation evidence. Protocol: `pub` profile,
unified seed `get_cec_seed(20240620, dim, func, run)`, Threefry substreams,
`NP = 5*D`, full suite budgets.

| Suite | DT-GSK tables | Runs |
|---|---|---|
| `cec2011` | `dt-gsk_cec2011_D<dim>.csv` per native dimension + `dt-gsk_cec2011.csv` rollup | 25 |
| `cec2013` | `D10`, `D30`, `D50` | 51 |
| `cec2013lsgo` | `D1000` (13 functions), `D905` (F13, F14) | 25 |
| `cec2017` | `D10`, `D30`, `D50`, `D100` | 51 |
| `cec2020` | `D5`, `D10`, `D15`, `D20` (`D5` has no F6/F7 rows) | 30 |

`cec2017/dt-gsk/PROVENANCE.md` records the source repository, tag and commit,
the producing commit and run date of each suite, and the protocol.
`cec2017/dt-gsk/evidence/` holds the reference campaign's per-run evidence
(`per_run.csv`, `seed_schedule.csv`, `environment.json`, `run_config.json`,
`phase0_protocol.json`, `verification.json`), the input for
`scripts/compare_reference_runs.m`. The reference's curated curves and
generation logs were not imported. The DT-GSK CEC2020 tables include F1 and F8
at `D5` and `D15`, cells this project's CEC2020 port reports as data-gap SKIPs
(see [porting_notes.md](porting_notes.md)), so those rows have no generated
counterpart.

Generated local results must go under `results/` and must never overwrite these
imported or curated references. If a future study promotes a generated
trajectory into this folder, record the source run metadata before doing so.

## Ground-Truth Test Data

The expected-value data used by C++ and MATLAB smoke tests is committed under:

```text
gsk_family/benchmarks/cec_suite_cpp/cec_tools/tests/data/
```

This project no longer carries scripts that require an external local reference
folder to regenerate that data. Treat the committed files as the validation
oracle unless a future, explicitly documented re-import is performed.
