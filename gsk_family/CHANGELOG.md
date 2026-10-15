# Changelog

All notable changes to `gsk_family` are recorded here. The format follows
Keep a Changelog; this project uses semantic versioning.

## [Unreleased]

### Added
- DT-GSK (`dt-gsk`), the seventh optimizer: a MATLAB port of the DT-GSK
  reference implementation v2.46 (MIT license) in three files under
  `src/optimizers/dt-gsk/` (`dt_gsk_optimize.m`, `dt_gsk_config.m` with the
  `pub` profile by dimension tier, `dt_gsk_graph.m` with the D >= 50
  interaction graph). NP = 5*D with nonlinear population reduction, four
  dimension tiers, always the full budget. Validated against the unmodified
  reference implementation on identical random numbers; details in its `README.md`.
- Unified-only seeding for DT-GSK: `run_experiment` schedules it with
  `get_cec_seed` and `threefry` under every `seed_policy` and draws no runner
  X0 for it (DT-GSK self-initializes from its own Threefry substream; documented
  fair-start exception, recorded in the run metadata).
- Imported DT-GSK reference results under
  `benchmarks/cec_reference_results/<suite>/dt-gsk/` for cec2011 (25 runs),
  cec2013 (51), cec2013lsgo (25), cec2017 (51) and cec2020 (30), with
  `cec2017/dt-gsk/PROVENANCE.md` and per-run `cec2017/dt-gsk/evidence/`
  (ignored by the reference loader). `gsk_list --references` now loads 165
  files / 1411 rows.
- `scripts/compare_reference_runs.m`: per-(dimension, function) comparison of
  two `per_run.csv` sets (Best/Median/Mean each within an order of magnitude,
  both sides rounded to the reference file's 11 significant digits,
  two-sided Wilcoxon rank-sum, paired signed-rank when seeds match,
  Holm-adjusted p-values; needs the Statistics and Machine Learning Toolbox).
- CLI support: `gsk_run` and `gsk_list --optimizers` know `dt-gsk` (seven
  optimizers); `configs/all_cec2017.yml`, `configs/all_cec2011.yml` and
  `default_experiment_matrix.m` include it. New MATLAB test
  `test_dt_gsk_smoke.m` (13 MATLAB tests in total).

### Fixed
- Runner resume: a `per_run.csv` row is reused only when its seed, cell budget
  (`max_nfes`) and effective generator all match the active run; other run ids
  are re-run and appended. `per_run.csv` gains trailing `max_nfes,rand_generator`
  columns (an older 11-column file is archived and upgraded once) and stores
  `best_fitness`/`error` with `%.17g`, so resumed summaries equal uninterrupted
  ones. Reused runs re-record the active seed in `seed_schedule.csv`, and after a
  resume only the median run's curve is kept (others move to `curves/_archive/`).
- Runner validation: an `output_dir` inside `benchmarks/cec_reference_results` is
  refused on every run (`run_experiment:outputUnsafe`); `seed_policy` is
  validated case-insensitively and `rand_generator` `auto`/`default` is rejected
  with `native`/`derived` (`run_experiment:args`); relative paths resolve
  against MATLAB's current folder.
- Reference-mode metadata records the seed formula actually used
  (`seed_formula`, `seed_policy.formula`) with per-optimizer strides (`null` for
  agsk/apgsk/fdb-agsk), and `seed_scheme` describes only the active optimizer.
  Seeds and RNG streams are unchanged.
- `CheckpointErrors` clip budget-crossing counters to `max_nfes`, so
  `E<max_nfes>` equals the per-run final error.
- `verify_unified_seed_schedule` compares seeds on keys present in two or more
  schedules; missing keys only warn (`missingKeys`), a `seedMismatch` fails.
- ATMALS-GSK and FDB-AGSK report `result.nfes`/`convergence.nfes` clipped at
  `max_nfes` (internal counter and trajectory unchanged). ATMALS-GSK pool
  overrides without the hard-coded initial pick raise `atmals_gsk:options`;
  AGSK/APGSK reject `min_pop_size < 11` or `np_init < min_pop_size`
  (`<name>_optimize:options`) instead of crashing in the senior partition.
- MEX bridge: linked fully static (no MinGW runtime DLL needed at load time),
  and `gskcec_require_mex` forces a real load (`gskcec:mexNotLoadable`). `eval`
  rejects sparse `X`. Integer arguments (`function_id`, `dimension`, handle) must
  be finite and integer-valued (`gskcec:badInput`, no truncation). Live handles
  `mexLock` the bridge so `clear mex` cannot recycle handle ids.
- `gsk_validate`: optimizer/suite/dimension come from the summary file name and
  each row is judged under its own suite and reference row; `--verify` reads
  the protocol from `summary/environment.json` unless `--reduced`/`--full` is
  given; archive folders are skipped; failure reasons print `%.10g`; a bare
  `--reduced`/`--full` prints usage instead of reading past the arguments.
- `gsk_run`: strict one-integer flags (`--function 1,3`, `--runs 2.9` rejected;
  `--max-evaluations >= 0`); `seed` in `[0, 2^53]`; relative config
  `output_root`/`reference_root` resolve under `--root`; `data_root` and empty
  lists are rejected; a leading UTF-8 BOM is accepted; MATLAB literals are
  quoted; a multi-optimizer config runs every optimizer and returns the first
  nonzero exit code. `gsk_bench` validates `--iterations` and `--csv`.
- Scripts: `run_all.ps1` defers to each config's seed policy/generator;
  `build_docs.ps1` falls back to the built-in renderer for Pandoc older than
  3.8; `analyze_results.m` matches references by exact dimension, ignores archive
  trees, labels duplicate layouts, needs no Statistics Toolbox, and closes its
  files on error.
- CMake install now ships a package config, so `find_package(gskcec 1.0)` with
  `gskcec::gskcec` works.

### Changed
- Console result tables now keep resume/stale-seed notices out of the table body
  and print them afterward as compact `Resume notes`.
- `configs/all_cec2011.yml` uses `max_evaluations: 0` (suite default 150,000), so
  the 25-run campaign is verified as full protocol; the budget is unchanged.
- Tests: new ctest suite `gskcec_cli_exit_codes` (13 suites in total); new MATLAB
  tests `test_runner_fair_start.m` and `test_runner_resume.m`; serial-vs-parallel
  artifact equality in `test_seed_policy.m`; stronger RNG-restore, reduction-tie,
  target-error, ATMALS-GSK budget/`D == 1`/pool, and seed golden-value checks.
- Launcher comments corrected (log file names, `use_parallel`, function and
  dimension subsets); `default_experiment_matrix.m` is documented as a reference
  statement with no callers.

### Documentation
- Synchronized Markdown build instructions to distinguish C++ CLI rebuilds from
  MATLAB MEX bridge rebuilds.
- Updated CTest examples to use `ctest --test-dir build --output-on-failure` for
  clearer failure diagnostics.
- Synced the Markdown with the fixes above: result schema, resume rules, seed
  policy, MEX contract, CLI/config reference, troubleshooting entries, ctest
  count, and shifted code line references.
- Corrected documentation-only findings: the shipped reference-table inventory
  (all six original optimizers on CEC2011, `fdb-agsk` on CEC2017, `gsk` on CEC2013
  D10/30/50); the cec2013lsgo `error` column is the raw objective, not `NaN`;
  APGSK's default NP is 100; reference-mode generators are a project choice, not
  a replay of the archived AGSK/APGSK `twister` drivers; ATMALS-GSK memory
  weighting and its quadratic history cost; APGSK draw order; eGSK's soft IP
  budget; FDB-AGSK budget, draw order and donor helpers; overstated test
  coverage; `optimizers` is a required config key; `gsk_run` dimension error
  messages; launcher location; `run_experiment` writes no `verification.json`;
  per-run seeds are not stored in the JSON metadata.
- DT-GSK presented as the seventh optimizer in `README.md`, `SKILL.md`,
  `CITATION.cff`, `codemeta.json`, `LICENSES.md` (MIT reference, GPL-compatible)
  and the folder READMEs; new algorithm page `docs/algorithms/dt-gsk.md`.
- Docs: new beginner `RUNBOOK.md`; the detailed runbook is now
  `docs/getting-started/command_reference.md`.

## [1.0.0] - 2026-06-13

First public, publication-grade release.

### Benchmarks (standalone C++20, no MATLAB/R/MEX at runtime)
- Ported all five CEC suites and validated each against ground truth from the
  original reference implementations:
  - CEC2017 (30 functions) - max relative deviation 4.8e-15 vs the original MEX.
  - CEC2020 (10 functions, internal mapping preserved) - 2.8e-16.
  - CEC2013 (standard 28-function suite, converted from the R package; runs
    without R) - analytic + optimum-at-shift + self-regression at 0.
  - CEC2013LSGO (15 large-scale functions; only the C++ sources kept) - bit-exact vs
    the untouched reference.
  - CEC2011 (22 real-world problems; `.mat` assets converted to text) - WP-A/WP-B
    bit-exact, WP-C (MGA-DSM trajectories) ~1.9e-13, including a behavioural
    `ode45` replica for the ODE problems.

### Optimizers (MATLAB, faithful to the reference)
- GSK, AGSK, APGSK, ATMALS-GSK, eGSK, FDB-AGSK under `src/optimizers`, with the
  shared helpers, runners, and the deterministic seed policy. GSK/AGSK/APGSK
  reproduce the reference algorithm bodies bit-identically.

### Tooling
- `gsk_list`, `gsk_validate`, `gsk_run` CLIs; the strict YAML-subset config
  parser; the imported-reference loader; the results-vs-reference comparison.
- Optional `gskcec_eval` MEX bridge so MATLAB optimizers evaluate the exact C++
  ports (verified against ground truth at 0 deviation).
- `gsk_bench` micro-benchmark harness for the C++ hot paths.

### Quality, performance, docs (publication preparation)
- **Automatic post-run verification:** every `gsk_run` compares the
  result against the same optimizer's published table and writes a
  `CONSISTENT`/`DEVIATES` verdict (`verification.json`); exposed as
  `gsk_validate --verify`. Exits nonzero on `DEVIATES`.
- **Folder clarity:** imported reference tables live in
  `benchmarks/cec_reference_results`, while CEC ports, input data, and nested
  C++ tools live in `benchmarks/cec_suite_cpp`; `configs/`, `scripts/` READMEs; a
  folder-structure decision guide; `.gitignore`.
- **Code readability:** `docs/development/code_reading_guide.md` guided tour;
  every ported file cites its reference source.
- **Engineering:** warnings-as-errors clean (GCC 16, `-Werror`); `.clang-format`,
  `.clang-tidy`; CMake `install`/`export` rules; `GSKCEC_NATIVE` and
  `GSKCEC_WERROR` options; GitHub Actions CI (Linux GCC/Clang + Windows MSVC,
  sanitizers, language-contract checks).
- **Performance:** `GSKCEC_NATIVE` gives a numerically-identical ~15-36% speedup
  on the heavy configurations (`-ffp-contract=off` keeps it bit-exact); baseline
  and method in `docs/research/performance.md`.
- **Fixed a latent test bug:** `core_tests`/`reference_results_tests` used raw
  `assert`, a no-op under Release/NDEBUG; replaced with always-on checks so the
  tests really run in Release.
- **Documentation:** plain-language `explainer.md`, end-to-end `tutorial.md`,
  `glossary.md`, Doxygen config (`docs/Doxyfile`, `docs/reference/api.md`), and the full
  `docs/` reference set.
- **Metadata and licensing:** `CITATION.cff`, `codemeta.json`, and a
  GPL-3.0-or-later license resolution (forced by the CEC2013 derivative) with a
  full component-by-component analysis in `LICENSES.md`.

### Known follow-ups (human / compute)
- Optimizer-vs-reference statistics in the paper are pipeline-generated
  placeholders pending a full-protocol experiment run.
- Author ORCID/affiliation, repository DOI, and Zenodo archival are placeholders
  for the author to complete.
- License conclusion (GPL-3.0-or-later) is recommended pending the original
  authors' confirmation.
