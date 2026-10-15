# GSK Family Project Skill

Use this skill when working inside the `gsk_family` project root - the folder that
contains `src/`, `benchmarks/`, `docs/`, `scripts/`, `CMakeLists.txt`, and this
`SKILL.md`.

This is a hybrid **MATLAB + C++20** research toolkit for the Gaining-Sharing
Knowledge (GSK) optimizer family on five CEC benchmark suites. The six optimizers
are MATLAB (`src/`); the CEC benchmark problems and all tooling are standalone
C++20 (`benchmarks/`); the two halves meet at exactly one seam, the
`gskcec_eval` MEX bridge. Every experiment run is automatically checked against
the same optimizer's published reference table. The guiding rule everywhere is
*fidelity over cleverness*: reference numerics, including documented bugs, are
preserved verbatim; the only sanctioned modernization is deterministic seeding.
**No Python exists anywhere** (code, tooling, bindings, or the docs build).

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
3. **MATLAB optimizer layer** (`src/optimizers`, `src/common`): the six
   algorithms plus shared donor/selection/RNG helpers.
4. **Experiment layer**: the C++ config parser, the MATLAB runner
   `src/runners/run_experiment.m`, and the **optional** `gskcec_eval` MEX bridge
   (`benchmarks/cec_suite_cpp/cec_tools/src/mex_bridge`).
5. **Validation/reporting**: the four CLIs, the reference comparison
   (`.../src/experiment/comparison.cpp`), and both C++ and MATLAB tests.

The two boundaries are absolute and must never be crossed:

- The **C++ side never implements a GSK optimizer**.
- The **MATLAB side never parses a config** (one strict C++ parser owns that).

The bridge is enforced: each launcher calls `gskcec_require_mex(...)`, which
errors early with the exact build command if `build/mex/gskcec_eval.<mexext>`
is missing. The MEX `eval` command takes a **column-major D x NP** matrix (one
candidate per column) and returns a `1 x NP` fitness row; the MATLAB optimizers
evaluate the same ported C++ code the C++ tests validate.

## The six optimizers

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

Two termination contracts coexist: only AGSK and APGSK stop early on the
`1e-8` target; the other four run the full budget and zero the error only at the
end. eGSK in reference mode **requires** the Optimization Toolbox (`fmincon`)
and errors `egsk:fminconUnavailable` if absent (`options.use_fmincon=false` is
the only non-reference diagnostic opt-out).

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
`best_fitness - optimum`. Default experiment matrix: all six optimizers on
cec2017 and cec2011, with AGSK additionally on cec2020.

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
- Generator (`effective_rand_generator`): under `reference`,
  `agsk`/`apgsk`/`fdb-agsk`/`egsk`/`atmals-gsk` use the legacy `seed` stream
  (`mcg16807`) and `gsk` (plus any other) uses `twister`; under `unified` the
  whole family uses `threefry` when supported, else `twister`; under
  `native/derived` the requested generator is honored. `gsk_set_rng.m` configures
  the generator via `RandStream` so `rand`, `randi`, **and** `randperm` are all
  deterministic.
- **Defaults differ by entry point** (intentional): `run_experiment(...)` and
  the root `run_all_cec*.m` launchers default to `unified` + `threefry`; the
  `gsk_run` CLI, the shipped `configs/*.yml`, and `scripts/run_all.ps1` default
  to `reference` + `threefry`.
- **Fair-start X0** (unified only): the runner draws the `NP=100` population once
  (`src/common/gsk_init_population.m` = a single `rand(np,dim)` draw), captures
  the post-initialization RNG state, passes both into the optimizer
  (`options.initial_population`, `options.rng_state_after_initialization`), and
  each optimizer restores that state so the first random decision is identical
  across all six optimizers for the same `(dim,func,run)`. The launchers verify
  this with `verify_unified_seed_schedule`.
- **Wall-clock seeding is forbidden project-wide**; every seed is recorded in
  `seed_schedule.csv`, `per_run.csv`, and `environment.json`.

## Results and verification

Outputs land under `results/<optimizer>/<suite>/` (launchers write under
`results/_run_all/<optimizer>/<suite>/`): `summary/` (per-dimension
`Function,Best,Median,Mean,Worst,SD` tables, `per_run.csv`, `environment.json`,
`seed_schedule.csv`, `verification.json`), `curves/` (+ `graphs/*.png`),
`gen_logs/`. Reruns are append/resume: completed run ids are skipped only when
their stored seed still matches the active policy; refreshed fixed-name files are
archived under `_archive/<timestamp>/`; imported reference tables under
`benchmarks/cec_reference_results` are never written to.

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
- **No Python** anywhere (code, tooling, bindings, docs build).
- **No external GSK/CEC imports** - treat the committed MATLAB/C++ ports,
  imported reference-result tables, and provenance notes as the self-contained
  source of truth.
- **Never weaken a test tolerance** to make a change pass; ctest compares against
  committed ground-truth data.
- Public slugs are hyphenated (`atmals-gsk`, `fdb-agsk`); MATLAB function/file
  names use underscores (`atmals_gsk_optimize.m`). Keep both correct.
- The two CEC2013 suites stay separate and are never merged.
- Wall-clock seeding stays forbidden; the seed contract above is fixed.

## Folder rules

- Imported CEC reference evidence: `benchmarks/cec_reference_results` (read-only
  aggregate tables plus curated `curves/`, `curves/graphs/`, and `gen_logs/`
  assets; never write normal run results there).
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
- Seeding: `src/runners/get_cec_seed.m` (unified),
  `src/runners/derive_run_seed.m` (native/derived),
  `src/common/gsk_set_rng.m` (generator); fair-start helpers
  `src/common/gsk_init_population.m`,
  `src/common/gsk_initial_population_from_options.m`,
  `src/common/gsk_restore_rng_after_initialization.m`.
- Four CLIs in `build/`: `gsk_list`, `gsk_validate`, `gsk_run`, `gsk_bench`.
- MEX bridge build: `powershell -File scripts\build_mex_bridge.ps1` ->
  `build/mex/gskcec_eval.mexw64`.
- Expected-value test data: committed under
  `benchmarks/cec_suite_cpp/cec_tools/tests/data`. The external regeneration archive
  is not bundled, so do not add scripts that depend on a missing local reference
  folder.

## Documentation

The docs site is generated by `scripts/build_docs.ps1` (PowerShell + Pandoc,
with a built-in fallback renderer, plus Doxygen for the C++ API - **no Python**)
into `docs/html/`. `docs/index.html` is a redirect into that site. Source
Markdown under `docs/` is the source of truth, organized to mirror the sibling
Python project (`00-GSK_Family_Python/docs`):

```text
docs/
  index.md  index.html(redirect)  Doxyfile
  getting-started/  explainer, tutorial, user_guide, runbook, configuration, troubleshooting
  reference/        architecture, matlab_interface, api, module_dependencies, workflows,
                    result_schema, seed_policy, benchmark_protocol, benchmark_mapping,
                    diagrams, project_structure, reference_inventory, porting_notes,
                    cec2011_port_plan, glossary
  algorithms/       gsk, agsk, apgsk, fdb-agsk, atmals-gsk, egsk  (10-section skeleton)
  development/      developer_guide, contributor_guide, maintenance_guide,
                    extension_guide, code_reading_guide
  research/         researcher_handbook, reproducibility, performance,
                    validation_report, numerical_examples
  prompts/          REVIEW_PROMPT, DOCS_DEEP_REVIEW_PROMPT,
                    INLINE_DOCUMENTATION_REVIEW_PROMPT, llm_review_prompt,
                    documentation_review_prompt, documentation_parity_prompt
```

`build_docs.ps1` emits folder-prefixed flat output names (e.g.
`getting-started_tutorial.html`) and rewrites cross-links by resolved path with a
**unique-basename fallback**, so moved pages keep linking correctly. Keep the
docs mirrored with the Python project (the reusable
`docs/prompts/documentation_parity_prompt.md` drives that), keep
`docs/research/researcher_handbook.md` synchronized with algorithm/seed/protocol
behavior, and keep all review prompts under `docs/prompts/` (never as root-level
files). Keep license and provenance in `LICENSES.md`; do not reintroduce a
separate root `LICENSE` file.

## Before editing

1. Read `docs/reference/project_structure.md` and
   `docs/reference/architecture.md`.
2. Read `docs/research/researcher_handbook.md` for the high-level system model,
   worked examples, reproducibility rules, and safe extension boundaries.
3. Check `docs/reference/reference_inventory.md` and
   `docs/reference/porting_notes.md` for provenance and preserved quirks.
4. Check `LICENSES.md` before changing provenance, redistribution, or
   attribution text.
5. Confirm the target file belongs to the correct language area (MATLAB under
   `src/`, C++ under `benchmarks/`).
6. If behavior is unclear from the committed implementation and provenance notes,
   document the gap in `docs/reference/porting_notes.md` instead of inventing it.

## Build and verification

```powershell
# Language-contract checks (must return nothing):
rg --files . | rg '\.(py|pyx)$|cec2013\.cpp$'
rg --files benchmarks\cec_suite_cpp | rg '\.(m|R|c|py|pyx)$|cec2013\.cpp$'

# C++ build and tests (12 ctest suites):
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure

# MEX bridge (required before any MATLAB CEC experiment):
powershell -File scripts\build_mex_bridge.ps1

# MATLAB smoke tests (no MEX bridge needed):
matlab -batch "cd('src/tests'); run_matlab_smoke_tests"

# Documentation site:
powershell -File scripts\build_docs.ps1 -Clean
```

Rebuild the C++ tree after changes to C++ sources/headers, CMake files,
CLI/config parser code, comparison logic, benchmark ports, or C++ tests. Rebuild
the MEX bridge after changes to CEC suite source files or `src/mex_bridge/`
before running MATLAB CEC experiments. Rebuild the docs site after any Markdown,
script, or Doxygen change (never hand-edit `docs/html`). All ctest suites compare
against committed ground-truth data; do not weaken tolerances to make a change
pass.
