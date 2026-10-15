# DT-GSK reference evidence — provenance

The `dt-gsk` reference folders were imported from the DT-GSK reference
implementation (MIT license):

- Repository: <https://github.com/MostafaMassoud/DT-GSK>, local checkout tag
  `v2.46` (commit `64c70bb54125c9361b821939802ee4810fb7af50`), folder
  `benchmarks/cec_reference_results/<suite>/dt-gsk/`.
- Imported files: the aggregate `Function,Best,Median,Mean,Worst,SD` tables of
  every suite, plus — for CEC2017, the suite used to validate the MATLAB port —
  the per-run evidence in `evidence/` (`per_run.csv`, `seed_schedule.csv`,
  `environment.json`, `run_config.json`, `phase0_protocol.json`,
  `verification.json`). Curated convergence curves/gen-logs (~49 MB) were not
  imported; they remain in the source repository.

| Suite | Tables | Runs | Producing commit | Run date |
|---|---|---|---|---|
| cec2017 | D10, D30, D50, D100 | 51 | `251fc8cb87c6ec6aa8ff9c4c1ffe9493b14c29c7` | 2026-07-18 |
| cec2013 | D10, D30, D50 | 51 | `251fc8cb87c6ec6aa8ff9c4c1ffe9493b14c29c7` | 2026-07-18 |
| cec2011 | native dims + rollup | 25 | `251fc8cb87c6ec6aa8ff9c4c1ffe9493b14c29c7` | 2026-07-18 |
| cec2013lsgo | D1000, D905 | 25 | `62fc49b809d60e0c638fd4fbd4d9bade19e6b0e4` | 2026-07-26 |
| cec2020 | D5, D10, D15, D20 | 30 | `74646d138e2dd9239c14b83221407e1e9d22ba91` | 2026-07-29 |

Protocol (all suites): `pub` profile, unified seed
`get_cec_seed(20240620, dim, func, run)`, Threefry substreams, NP = 5*D,
full budgets (`10000*D` for CEC2017/CEC2013), the reference implementation's
compiled kernels, single-threaded (runtime versions are recorded in
`evidence/environment.json`). The CEC2017 reference `verification.json`
verdict is `CONSISTENT` over 116 cells.

These tables are the comparison baseline for the MATLAB port
`src/optimizers/dt-gsk/` (see `src/optimizers/dt-gsk/README.md` for the port
record and validation). They were produced by the reference implementation, not
by this toolkit, so agreement with them is cross-implementation evidence.
