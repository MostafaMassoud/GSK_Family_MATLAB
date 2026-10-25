# GSK Family Project Skill

Use this skill when working inside the `gsk_family` project root - the folder that
contains `src/`, `benchmarks/`, `docs/`, `scripts/`, `CMakeLists.txt`, and this
`SKILL.md`. For the current state, open decisions and next steps read
`../CLAUDE.md`; for step-by-step task playbooks (campaigns, validation,
comment-only edits, numerics-preserving changes) use the `gsk-family` skill in
`../.claude/skills/gsk-family/SKILL.md`.

This is a hybrid **MATLAB + C++20** research toolkit for the Gaining-Sharing
Knowledge (GSK) optimizer family on five CEC benchmark suites. The seven optimizers
are MATLAB (`src/`); the CEC benchmark problems and all tooling are standalone
C++20 (`benchmarks/`); the two halves meet at exactly one seam, the
`gskcec_eval` MEX bridge. `gsk_run` checks every run against the same
optimizer's published reference table (`verification.json`); launcher and
direct `run_experiment` runs print a comparison table, and
`gsk_validate --verify` gives the verdict. The guiding rule everywhere is
*fidelity over cleverness*: reference numerics, including documented bugs, are
preserved verbatim; the only sanctioned modernization is deterministic seeding.
**MATLAB and C++ only** (no other languages or generated bindings; helper
scripts, including the docs build, are PowerShell or MATLAB).

## Architecture: five layers, two hard boundaries

1. **C++ core** (`benchmarks/cec_suite_cpp/cec_tools/include/gskcec/core`): numeric
   types (`Real=double`, `Seed=uint64_t`), `Bounds` (reference midpoint repair),
   summary statistics, stopwatch.
2. **C++ benchmark layer** (`benchmarks/cec_suite_cpp/*/src`,
   `.../include/gskcec/benchmark`): one immutable `BenchmarkProblem` per
   (suite, function, dimension) exposing `evaluate(x)`, `bounds()`,
   `optimum()`, `dimension()`; built by `gskcec::make_problem(suite, function,
   dimension, data_root)`. Data loads from explicit paths at construction (no
   CWD dependence); a single instance is **not thread-safe** (one per thread).
3. **MATLAB optimizer layer** (`src/optimizers`, `src/common`): the seven
   algorithms plus shared donor/selection/RNG helpers (DT-GSK is
   self-contained and uses none of them).
4. **Experiment layer**: the C++ config parser, the MATLAB runner
   `src/runners/run_experiment.m`, and the **optional** `gskcec_eval` MEX bridge
   (`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge`).
5. **Validation/reporting**: the four CLIs, the reference comparison
   (`.../src/experiment/comparison.cpp`), and both C++ and MATLAB tests.

The two boundaries are absolute and must never be crossed:

- The **C++ side never implements a GSK optimizer**.
- The **MATLAB side never parses a config** (one strict C++ parser owns that).

The bridge is enforced: each launcher (and `run_experiment` for CEC suites)
calls `gskcec_require_mex(...)`, which errors early with the exact build command
if `build/mex/gskcec_eval.<mexext>` is missing or cannot be loaded
(`gskcec:mexNotLoadable`; it forces a real load). The MEX `eval` command takes a **column-major D x NP** matrix (one
candidate per column) and returns a `1 x NP` fitness row; the MATLAB optimizers
evaluate the same ported C++ code the C++ tests validate.

## The seven optimizers

Public slugs are hyphenated; MATLAB entry-point function/file names use
underscores. Folders sit under `src/optimizers/<slug>/`.

| Slug | Entry point | One line | Stops early on target? |
|---|---|---|---|
| `gsk` | `gsk_optimize.m` | baseline gaining-sharing knowledge | no (always `max_evaluations`) |
| `agsk` | `agsk_optimize.m` | adaptive parameter pools + LPSR population reduction | yes (`target_error_reached`) |
| `apgsk` | `apgsk_optimize.m` | negative/contracting KF pool + stochastic junior schedule | yes (`target_error_reached`) |
| `atmals-gsk` | `atmals_gsk_optimize.m` | five-parameter roulette adaptation + local search | no |
| `egsk` | `egsk_optimize.m` | separate KF1/KF2, late-stage adaptation, fmincon/SQP refinement | no |
| `fdb-agsk` | `fdb_agsk_optimize.m` | fitness-distance-balance donor selection (5 cases) | no |
| `dt-gsk` | `dt_gsk_optimize.m` | dimension-tiered GSK: NP = 5*D with nonlinear reduction; four tiers (D < 20, 20 <= D < 50, D >= 50, D >= 100) switch on adaptive parameter selection, linkage crossover, escapes/restarts, local search, and from D = 50 an interaction graph plus final polish | no |

Two termination contracts coexist: only AGSK and APGSK stop early on the
`1e-8` target; the other five run the full budget and zero the error only at the
end. eGSK in reference mode **requires** the Optimization Toolbox (`fmincon`)
and errors `egsk:fminconUnavailable` if absent (`options.use_fmincon=false` is
the only non-reference diagnostic opt-out). DT-GSK is three code files
(`dt_gsk_optimize.m`, `dt_gsk_config.m` = the `pub` profile by tier,
`dt_gsk_graph.m` = the D >= 50 interaction graph); its `README.md` is the
authoritative behavior and validation record (a MATLAB port of the MIT-licensed
reference implementation v2.46).

## The five benchmark suites

| Suite | Functions | Dimensions | Budget (`max_nfes`) | Optima | Statistics basis |
|---|---|---|---|---|---|
| `cec2017` | 30 (F2 excluded from default comparisons) | 10, 30, 50, 100 | `10000*D` | `100*fid` | error vs optimum |
| `cec2020` | 10 | 5, 10, 15, 20 | 50k / 1M / 3M / 10M | vector (AGSK source) | error vs optimum |
| `cec2013` | 28 | 2..100 | `10000*D` | biases -1400..+1400 | error vs optimum |
| `cec2013lsgo` | 15 | 1000 native (905 for F13/F14) | 3,000,000 | 0 by construction (reported raw) | raw objective |
| `cec2011` | 22 | fixed native per problem | 150,000 | none (`NaN`) | raw objective |

The two CEC2013 suites (`cec2013`, `cec2013lsgo`) are **separate and never
merged**. Known-optimum suites apply the standard `1e-8` zero cutoff to errors.
**Reporting exception:** ATMALS-GSK on CEC2017 reports `abs(best_fitness -
optimum)` with the `1e-8` cutoff; every other case reports the signed
`best_fitness - optimum`. Default experiment matrix: all seven optimizers on
cec2017 and cec2011, with AGSK additionally on cec2020 (DT-GSK also has imported
references for cec2013, cec2013lsgo and cec2020).

## Seed and RNG contract

- Default `base_seed = 20240620`, centralized in `src/runners/run_experiment.m`.
- Four policies: `reference`, `unified`, `native` (`derived` is an alias of
  `native`).
  - **unified** (`src/runners/get_cec_seed.m`), optimizer-independent:

    ```text
    seed = mod(base_seed + 1000003*dim + 1000033*func + 1000037*run, 2147483646) + 1
    ```

    Do NOT add optimizer name, optimizer index, population size, budget, or
    suite name to this formula. (`get_cec_seed(20240620,30,7,12) = 69241386`.)
  - **reference** (per optimizer): `gsk`/`egsk`/`atmals-gsk` use
    `base_seed + 9973*func + (run-1)`; `agsk`/`apgsk`/`fdb-agsk` use `D*func*run`.
  - **native/derived** (`src/runners/derive_run_seed.m`): a diagnostic hash that
    also folds in optimizer + suite identity (not a fair-start policy).
- **Unified-only exception (`dt-gsk`)**: `run_experiment` (`is_unified_only`)
  schedules DT-GSK with `get_cec_seed(base_seed, dim, func, run)` and
  `threefry` under **every** `seed_policy` (`reference`/`unified`/`native`/
  `derived`), mirroring the reference implementation's `UNIFIED_ONLY_OPTIMIZERS`: its
  reference campaign was produced that way. DT-GSK derives named Threefry
  substreams from the run seed, never touches the global RNG, and requires
  `options.rand_generator` = `threefry` (empty/`auto`/`default` accepted).
- Generator (`effective_rand_generator`): under `reference`,
  `agsk`/`apgsk`/`fdb-agsk`/`egsk`/`atmals-gsk` use the legacy `seed` stream
  (`mcg16807`) and `gsk` uses `twister`; under `unified` the whole family uses
  `threefry` when supported, else `twister`; under `native/derived` the
  requested generator is honored; `dt-gsk` is always `threefry`. `gsk_set_rng.m`
  configures the generator via `RandStream` so `rand`, `randi`, **and**
  `randperm` are all deterministic. The reference generator is a fixed project
  choice, not a replay of every historical driver (the archived AGSK/APGSK
  drivers seed with `twister`).
- **Defaults differ by entry point** (intentional): `run_experiment(...)` and
  the root `run_all_cec*.m` launchers default to `unified` + `threefry`; the
  `gsk_run` CLI, the shipped `configs/*.yml`, and `scripts/run_all.ps1` default
  to `reference` + `threefry` (`run_all.ps1` defers to each config's
  `seed_policy` / `rand_generator` unless `-SeedPolicy` / `-RandGenerator` is
  passed). `run_experiment` rejects any other `seed_policy`
  (case-insensitive match) and `rand_generator` `auto`/`default` under
  `native`/`derived` with `run_experiment:args`.
- **Fair-start X0** (unified only): the runner draws the `NP=100` population once
  (`src/common/gsk_init_population.m` = a single `rand(np,dim)` draw), captures
  the post-initialization RNG state, passes both into the optimizer
  (`options.initial_population`, `options.rng_state_after_initialization`), and
  each optimizer restores that state so the first random decision is identical
  across the six original optimizers for the same `(dim,func,run)`. DT-GSK is
  the documented fair-start exception: it samples its own `NP = 5*D` population
  and ignores a runner X0, so the runner draws none for it (the metadata
  `initial_population_policy` reads "optimizer self-initializes NP = 5*D ..."
  and `run_config.json` records `profile: pub`). The launchers verify the seed
  schedule with `verify_unified_seed_schedule` (seeds compared on keys present
  in two or more schedules; missing keys only warn).
- **Wall-clock seeding is forbidden project-wide**; every per-run seed is
  recorded in `seed_schedule.csv`, `per_run.csv`, and the `gen_logs/` `Seed`
  column, and `environment.json` / `run_config.json` record `base_seed`, the
  scheme, and the seed formula.

## Results and verification

Outputs land under `results/<optimizer>/<suite>/` (launchers write under
`results/_run_all/<optimizer>/<suite>/`): `summary/` (per-dimension
`Function,Best,Median,Mean,Worst,SD` tables, `per_run.csv`, `environment.json`,
`seed_schedule.csv`, `verification.json`), `curves/` (+ `graphs/*.png`),
`gen_logs/`. Reruns are append/resume: completed run ids are skipped only when
their stored seed, budget (`max_nfes`) and effective generator still match the
active run (other rows are re-run and appended; stale rows stay as history);
refreshed fixed-name files are archived under `_archive/<timestamp>/`. Each
dimension's summary tables are written as soon as that dimension finishes, so a
crash later in the call keeps them; `environment.json` and `run_config.json`
describe the dimensions and functions of the latest call, so after chunked runs
finish with one pass over everything (all runs are reused). Imported
reference tables under `benchmarks/cec_reference_results` are never written to
(`run_experiment` refuses any `output_dir` inside that tree with
`run_experiment:outputUnsafe`).

Each `gsk_run` auto-writes `verification.json` with verdict `CONSISTENT` or
`DEVIATES` (gsk_run exits nonzero on `DEVIATES`; `--no-verify` opts out). The
three hard-failure checks (catch implementation bugs, not optimization quality):
non-finite statistics; on known-optimum suites a best error below
`negative_error_floor = -1e-6`; and, at full protocol only, a mean above
`gross_factor = 1e6` times a non-trivial (`> reference_trivial_floor = 1e-8`)
reference mean. `reduced_budget` (overridden budget OR `< 25` runs) makes the
gross-deviation check and the win/tie/loss tally informational. The two senses of
"correct" stay distinct: benchmark **ports** are checked exactly against
fixed-vector ground truth (C++ tests); **optimizers** are checked statistically
here.

## Non-negotiable preservation rules

- **Preserve reference behavior, including documented quirks/bugs** - read
  `docs/reference/porting_notes.md` before "fixing" anything that looks wrong.
- **MATLAB and C++ only** (no other languages or generated bindings; helper
  scripts, including the docs build, are PowerShell or MATLAB). Comments and
  docs never name the reference implementation's language or its libraries;
  say "the reference implementation".
- The launchers' CONFIG values (`../run_all_cec*.m`) belong to the owner: edit
  their comments only.
- When a campaign disagrees with a reference, report the difference with a
  likely explanation; never tune an optimizer to force agreement.
- **No external GSK/CEC imports** - treat the committed MATLAB/C++ ports,
  imported reference-result tables, and provenance notes as the self-contained
  source of truth.
- **Never weaken a test tolerance** to make a change pass; ctest compares against
  committed ground-truth data.
- Public slugs are hyphenated (`atmals-gsk`, `fdb-agsk`, `dt-gsk`); MATLAB
  function/file names use underscores (`atmals_gsk_optimize.m`,
  `dt_gsk_optimize.m`). Keep both correct.
- The two CEC2013 suites stay separate and are never merged.
- Wall-clock seeding stays forbidden; the seed contract above is fixed.

## Folder rules

- Imported CEC reference evidence: `benchmarks/cec_reference_results` (read-only
  aggregate tables plus curated `curves/`, `curves/graphs/`, and `gen_logs/`
  assets, and for `cec2017/dt-gsk/` a per-run `evidence/` subfolder and
  `PROVENANCE.md`; never write normal run results there). The reference loader
  reads only tables directly under `<suite>/<optimizer>/`
  (`gsk_list --references` loads 165 files / 1411 rows).
- CEC C++ ports and CEC input data: `benchmarks/cec_suite_cpp/<suite>/{src,input_data}`.
- CEC support headers, library, CLIs, MEX bridge, C++ tests:
  `benchmarks/cec_suite_cpp/cec_tools`.
- MATLAB GSK code: `src/{common,optimizers,runners,experiments,tests}`.
- Documentation: `docs` (see the taxonomy below). PowerShell/MATLAB helper
  scripts: `scripts`.
- Generated experiment outputs: `results/` only. Generated build/site trees
  (`build/`, `docs/html/`) are not source of truth and are never hand-edited.

Do not create root-level `reference_results`, root-level `data/cec*`, top-level
`include`, top-level `tests`, or top-level `matlab` folders. Do not put CEC code
under `src` or GSK code under `benchmarks`.

## Key entry points

- C++ problem construction: `gskcec::make_problem(suite, func, dim, data_root)`
  (`benchmarks/cec_suite_cpp/cec_tools/include/gskcec/benchmark/factory.hpp`).
- MATLAB problem construction: `src/runners/gskcec_make_problem.m` (CEC suites
  via the `gskcec_eval` MEX bridge; the `sphere` test suite is pure MATLAB).
- Experiment driver: `gsk_run` CLI -> `src/runners/run_experiment.m`; or the
  root `run_all_cec*.m` launchers; or a direct `run_experiment(...)` call.
- Optimizers: `src/optimizers/<slug>/<slug_with_underscores>_optimize.m`; DT-GSK
  is `src/optimizers/dt-gsk/dt_gsk_optimize.m` (+ `dt_gsk_config.m`,
  `dt_gsk_graph.m`; validation record in its `README.md`). A new optimizer:
  `scripts/new_gsk_variant.m` (renamed copy of one of the seven; no
  registration needed for MATLAB runs).
- Aliases: `algorithms.ini` in the repository root, read by
  `src/runners/read_algorithm_aliases.m`. `run_experiment` resolves an alias
  to its base (`resolve_alias`): the base decides code, seeds and options,
  the alias names files and results (`a.name`), and `alias_setting_names`
  lists the settings each base accepts. `test_algorithm_aliases.m` covers it.
- Comparison of optimizers with each other: `run_compare_algorithms.m` (root)
  -> `scripts/plot_convergence.m` (curves, IQR bands),
  `scripts/compare_algorithms.m` (Mean/SD, rank-sum with Holm and A12,
  signed-rank, Friedman with Iman-Davenport, post-hoc Holm/Hochberg/Finner,
  Nemenyi CD, settings tables), `scripts/plot_statistics.m` (CD diagram, box
  plots, rank charts) and, opt-in, `scripts/cec_complexity.m` (CEC
  complexity table; it runs the optimizers), `scripts/plot_performance.m`
  (success rate, ERT, ECDF; dense data with the runner's `trace_points`),
  and `scripts/make_study_aliases.m` with `plot_sensitivity.m` and
  `plot_ablation.m`. `test_comparison_tools.m` covers them.
- Run-level comparison of two `per_run.csv` sets (e.g. a MATLAB DT-GSK campaign
  vs `benchmarks/cec_reference_results/cec2017/dt-gsk/evidence/per_run.csv`):
  `scripts/compare_reference_runs.m` (needs the Statistics and Machine Learning
  Toolbox). A function MATCHes when the two-sided rank-sum p >= 0.05 and Best,
  Median and Mean agree within one decade; both sides are first rounded to 11
  significant digits (`sig_digits`, the reference file's precision).
- Seeding: `src/runners/get_cec_seed.m` (unified),
  `src/runners/derive_run_seed.m` (native/derived),
  `src/common/gsk_set_rng.m` (generator); fair-start helpers
  `src/common/gsk_init_population.m`,
  `src/common/gsk_initial_population_from_options.m`,
  `src/common/gsk_restore_rng_after_initialization.m`.
- Four CLIs in `build/`: `gsk_list`, `gsk_validate`, `gsk_run`, `gsk_bench`
  (`gsk_run` and `gsk_list --optimizers` know all seven slugs).
- MEX bridge build: `powershell -File scripts\build_mex_bridge.ps1` ->
  `build/mex/gskcec_eval.mexw64` (linked fully static: no MinGW runtime DLL is
  needed at load time).
- Expected-value test data: committed under
  `benchmarks/cec_suite_cpp/cec_tools/tests/data`. The external regeneration archive
  is not bundled, so do not add scripts that depend on a missing local reference
  folder.

## Documentation

The docs site is generated by `scripts/build_docs.ps1` (PowerShell + Pandoc 3.8+,
with a built-in fallback renderer used when Pandoc is absent or older, plus
Doxygen for the C++ API)
into `docs/html/`. `docs/index.html` is a redirect into that site. Source
Markdown under `docs/` is the source of truth, organized to mirror the sibling
project's docs (`<sibling-project>/docs`):

```text
docs/
  index.md  index.html(redirect)  Doxyfile
  getting-started/  explainer, tutorial, user_guide, command_reference, configuration, troubleshooting
  reference/        architecture, matlab_interface, api, module_dependencies, workflows,
                    result_schema, seed_policy, benchmark_protocol, benchmark_mapping,
                    diagrams, project_structure, reference_inventory, porting_notes,
                    cec2011_port_plan, glossary
  algorithms/       gsk, agsk, apgsk, fdb-agsk, atmals-gsk, egsk, dt-gsk  (10-section skeleton;
                    the DT-GSK validation record is src/optimizers/dt-gsk/README.md)
  development/      developer_guide, contributor_guide, maintenance_guide,
                    extension_guide, code_reading_guide
  research/         researcher_handbook, reproducibility, performance,
                    validation_report, numerical_examples
  prompts/          REVIEW_PROMPT, DOCS_DEEP_REVIEW_PROMPT,
                    INLINE_DOCUMENTATION_REVIEW_PROMPT, llm_review_prompt,
                    documentation_review_prompt, documentation_parity_prompt
```

Newcomers start at `RUNBOOK.md` in the repository root (`../RUNBOOK.md`, one
level above gsk_family; prerequisites, first run from the MATLAB desktop and
from a terminal, parallel runs in MATLAB). `build_docs.ps1` also writes
`../RUNBOOK.html`, a single-page copy (never hand-edit it); the root
`../README.md` is the short landing page;
`docs/getting-started/command_reference.md` holds the detailed run commands for
every algorithm.

`build_docs.ps1` emits folder-prefixed flat output names (e.g.
`getting-started_tutorial.html`) and rewrites cross-links by resolved path with a
**unique-basename fallback**, so moved pages keep linking correctly. Keep the
docs mirrored with the sibling project's docs (the reusable
`docs/prompts/documentation_parity_prompt.md` drives that), keep
`docs/research/researcher_handbook.md` synchronized with algorithm/seed/protocol
behavior, and keep all review prompts under `docs/prompts/` (never as root-level
files). Keep license and provenance in `LICENSES.md`; do not reintroduce a
separate root `LICENSE` file.

## Before editing

1. Read `../CLAUDE.md` (current state, open decisions, next steps). With this
   file and the `gsk-family` skill it is enough for campaign, validation and
   docs work; read the documents below only when the task touches their area.
2. Before touching optimizer or port numerics: `docs/reference/porting_notes.md`
   (preserved quirks) and `docs/reference/reference_inventory.md` (provenance).
3. For a system-level change: `docs/reference/architecture.md`,
   `docs/reference/project_structure.md`, `docs/research/researcher_handbook.md`.
4. Check `LICENSES.md` before changing provenance, redistribution, or
   attribution text.
5. Confirm the target file belongs to the correct language area (MATLAB under
   `src/`, C++ under `benchmarks/`).
6. If behavior is unclear from the committed implementation and provenance notes,
   document the gap in `docs/reference/porting_notes.md` instead of inventing it.

## Build and verification

`rg` is ripgrep; if it is not installed, run the same patterns with Claude
Code's Grep tool.

```powershell
# Language-contract checks (must return nothing):
rg --files . | rg '\.(py|pyx)$|cec2013\.cpp$'
rg --files benchmarks\cec_suite_cpp | rg '\.(m|R|c|py|pyx)$|cec2013\.cpp$'

# C++ build and tests (13 ctest suites, incl. the gskcec_cli_exit_codes CLI test):
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure

# MEX bridge (required before any MATLAB CEC experiment):
powershell -File scripts\build_mex_bridge.ps1

# MATLAB smoke tests (15 tests, incl. test_dt_gsk_smoke; no MEX bridge needed):
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"

# Documentation site (also regenerates ../RUNBOOK.html):
powershell -File scripts\build_docs.ps1 -Clean
```

For parallel experiments open the pool before calling the runner (8 process
workers on a 32 GB machine; about 2 to 3 GB per worker); otherwise
`run_experiment` starts one worker per physical core.

Rebuild the C++ tree after changes to C++ sources/headers, CMake files,
CLI/config parser code, comparison logic, benchmark ports, or C++ tests. Rebuild
the MEX bridge after changes to CEC suite source files or `src/mex_bridge/`
before running MATLAB CEC experiments. Rebuild the docs site after any Markdown,
script, or Doxygen change (never hand-edit `docs/html`). All ctest suites compare
against committed ground-truth data; do not weaken tolerances to make a change
pass.
